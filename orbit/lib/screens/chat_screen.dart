import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/media_repository.dart';
import '../data/orbit_import_sink.dart';
import '../data/services.dart';
import '../import/util/address.dart';
import '../models/models.dart';
import '../services/audio_recorder_service.dart';
import '../services/file_pick.dart';
import '../services/platform_caps.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/media_pickers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/user_profile_builder.dart';
import 'group_info_screen.dart';
import 'inbox_screen.dart';
import 'user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Upload {
  _Upload(this.label);
  final String label;
  double progress = 0;
}

enum _Attach { photo, camera, video, document, gif, sticker }

class _ChatScreenState extends State<ChatScreen> {
  static const _pageSize = 40;

  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _inputFocus;

  late final OrbitServices _services;
  late final Session _session;

  StreamSubscription<Conversation?>? _conversationSub;
  StreamSubscription<List<Message>>? _messagesSub;
  Conversation? _conversation;
  bool _conversationMissing = false;
  List<Message> _messages = const [];
  bool _messagesLoaded = false;
  String? _messagesError;
  int _limit = _pageSize;
  bool _loadingMore = false;
  DateTime? _lastMarkedRead;

  final List<_Upload> _uploads = [];

  AudioRecorderService? _recorder;
  bool _recording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;

  bool get _hasMore => _messages.length >= _limit;

  @override
  void initState() {
    super.initState();
    _services = context.read<OrbitServices>();
    _session = context.read<Session>();
    _inputFocus = FocusNode(onKeyEvent: _onComposerKey);
    _scroll.addListener(_onScroll);
    _conversationSub =
        _services.chats.watchConversation(widget.conversationId).listen(
      (c) {
        setState(() {
          _conversation = c;
          _conversationMissing = c == null;
        });
        _maybeMarkRead();
      },
      onError: (_) => setState(() => _conversationMissing = true),
    );
    _subscribeMessages();
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    _messagesSub?.cancel();
    _recordTimer?.cancel();
    _recorder?.dispose();
    _text.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _subscribeMessages() {
    _messagesSub?.cancel();
    _messagesSub = _services.chats
        .watchMessages(widget.conversationId, limit: _limit)
        .listen((messages) {
      setState(() {
        _messages = messages;
        _messagesLoaded = true;
        _messagesError = null;
        _loadingMore = false;
      });
      _maybeMarkRead();
    }, onError: (Object e) {
      setState(() {
        _messagesError = 'Could not load messages.';
        _loadingMore = false;
      });
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      setState(() {
        _loadingMore = true;
        _limit += _pageSize;
      });
      _subscribeMessages();
    }
  }

  void _maybeMarkRead() {
    final c = _conversation;
    if (c == null || !c.hasUnreadFor(_session.uid)) return;
    final now = DateTime.now();
    if (_lastMarkedRead != null &&
        now.difference(_lastMarkedRead!) < const Duration(seconds: 2)) {
      return;
    }
    _lastMarkedRead = now;
    _services.chats.markRead(c.id, _session.uid).catchError((_) {});
  }

  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _sendText();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToNewest() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  // Sending

  void _send({
    required MessageKind kind,
    String text = '',
    List<Attachment> attachments = const [],
    String? messageId,
  }) {
    // Firestore applies the write locally right away and syncs when online,
    // so the UI does not wait for the server.
    unawaited(_services.chats
        .sendMessage(
          conversationId: widget.conversationId,
          senderId: _session.uid,
          senderName: _session.displayName,
          kind: kind,
          text: text,
          attachments: attachments,
          messageId: messageId,
        )
        .then<void>(
          (_) {},
          onError: (Object _) =>
              _toast('Message not sent. Check your connection.'),
        ));
    _scrollToNewest();
  }

  void _sendText() {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    _send(kind: MessageKind.text, text: body);
  }

  Future<(int?, int?)> _imageSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (descriptor.width, descriptor.height);
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _uploadAndSend(
    PickedFile file, {
    required AttachmentKind attachmentKind,
    required MessageKind messageKind,
    int? durationMs,
  }) async {
    if (file.bytes.length > MediaRepository.maxUploadBytes) {
      _toast('Files must be under 50 MB.');
      return;
    }
    final upload = _Upload(file.name);
    setState(() => _uploads.add(upload));
    try {
      int? width;
      int? height;
      if (attachmentKind == AttachmentKind.image ||
          attachmentKind == AttachmentKind.gif) {
        (width, height) = await _imageSize(file.bytes);
      }
      final messageId = _services.chats.newMessageId(widget.conversationId);
      final attachment = await _services.media.uploadChatFile(
        conversationId: widget.conversationId,
        uploaderUid: _session.uid,
        kind: attachmentKind,
        bytes: file.bytes,
        fileName: file.name,
        mimeType: file.mimeType,
        width: width,
        height: height,
        durationMs: durationMs,
        onProgress: (p) {
          if (mounted) setState(() => upload.progress = p);
        },
      );
      _send(
        kind: messageKind,
        attachments: [attachment],
        messageId: messageId,
      );
    } catch (e) {
      _toast('Upload failed. Try again.');
    } finally {
      if (mounted) setState(() => _uploads.remove(upload));
    }
  }

  Future<void> _attach(_Attach choice) async {
    try {
      switch (choice) {
        case _Attach.photo:
          final file = await pickFile(type: FileType.image);
          if (file == null) return;
          final gif = file.mimeType == 'image/gif';
          await _uploadAndSend(
            file,
            attachmentKind: gif ? AttachmentKind.gif : AttachmentKind.image,
            messageKind: gif ? MessageKind.gif : MessageKind.image,
          );
        case _Attach.camera:
          final file = await takePhoto();
          if (file == null) return;
          await _uploadAndSend(file,
              attachmentKind: AttachmentKind.image,
              messageKind: MessageKind.image);
        case _Attach.video:
          final file = await pickFile(type: FileType.video);
          if (file == null) return;
          await _uploadAndSend(file,
              attachmentKind: AttachmentKind.video,
              messageKind: MessageKind.video);
        case _Attach.document:
          final file = await pickFile();
          if (file == null) return;
          await _uploadAndSend(file,
              attachmentKind: AttachmentKind.document,
              messageKind: MessageKind.document);
        case _Attach.gif:
          if (!mounted) return;
          final pick = await showGifPicker(context, _services.gifs);
          switch (pick) {
            case GifSearchChoice(:final gif):
              _send(kind: MessageKind.gif, attachments: [
                Attachment(
                  kind: AttachmentKind.gif,
                  url: gif.url,
                  name: gif.title.isEmpty ? 'GIF' : gif.title,
                  mimeType: 'image/gif',
                  width: gif.width,
                  height: gif.height,
                ),
              ]);
            case GifFileChoice():
              final file = await pickFile(
                  type: FileType.custom, allowedExtensions: ['gif']);
              if (file == null) return;
              await _uploadAndSend(file,
                  attachmentKind: AttachmentKind.gif,
                  messageKind: MessageKind.gif);
            case null:
              return;
          }
        case _Attach.sticker:
          if (!mounted) return;
          final sticker = await showStickerPicker(context);
          if (sticker == null) return;
          _send(kind: MessageKind.sticker, attachments: [
            Attachment(kind: AttachmentKind.sticker, stickerId: sticker.id),
          ]);
      }
    } catch (e) {
      _toast('Could not open that file.');
    }
  }

  // Voice messages

  Future<void> _startRecording() async {
    final recorder = _recorder ??= AudioRecorderService();
    try {
      final started = await recorder.start();
      if (!started) {
        _toast('Microphone is not available. Check permissions.');
        return;
      }
    } catch (_) {
      _toast('Recording is not supported on this device.');
      return;
    }
    setState(() {
      _recording = true;
      _recordElapsed = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _recordElapsed += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _finishRecording({required bool send}) async {
    _recordTimer?.cancel();
    setState(() => _recording = false);
    final recorder = _recorder;
    if (recorder == null) return;
    if (!send) {
      await recorder.cancel();
      return;
    }
    try {
      final audio = await recorder.stop();
      if (audio == null || audio.bytes.isEmpty) {
        _toast('Nothing was recorded.');
        return;
      }
      await _uploadAndSend(
        PickedFile(
          bytes: audio.bytes,
          name: audio.fileName,
          mimeType: audio.mimeType,
        ),
        attachmentKind: AttachmentKind.audio,
        messageKind: MessageKind.audio,
        durationMs: audio.duration.inMilliseconds,
      );
    } catch (_) {
      _toast('Could not save the recording.');
    }
  }

  // Message actions

  Future<void> _openActions(Message message) async {
    final mine = message.isFrom(_session.uid);
    final myReaction = message.reactions[_session.uid];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final palette = MessengerPalette.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.deleted) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    children: [
                      for (final emoji in quickReactions)
                        Semantics(
                          button: true,
                          selected: myReaction == emoji,
                          label: 'React with $emoji',
                          excludeSemantics: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.pop(context, 'react:$emoji'),
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: myReaction == emoji
                                    ? palette.accent.withValues(alpha: 0.14)
                                    : palette.surface,
                                border: myReaction == emoji
                                    ? Border.all(
                                        color: palette.accent
                                            .withValues(alpha: 0.55),
                                      )
                                    : null,
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 23),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: palette.hairline),
              ],
              if (message.reactions.isNotEmpty && !message.deleted)
                ListTile(
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: const Text('See reactions'),
                  onTap: () => Navigator.pop(context, 'reactions'),
                ),
              if (message.text.isNotEmpty && !message.deleted)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy text'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              if (mine && !message.deleted && message.kind == MessageKind.text)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
              if (mine && !message.deleted)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: palette.danger,
                  ),
                  title: Text(
                    'Delete for everyone',
                    style: TextStyle(color: palette.danger),
                  ),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              if (message.senderId != null && !mine)
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text('View ${message.senderLabel}'),
                  onTap: () => Navigator.pop(context, 'profile'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action.startsWith('react:')) {
      _toggleReaction(message, action.substring(6));
    } else if (action == 'reactions') {
      _showReactions(message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      _toast('Copied.');
    } else if (action == 'edit') {
      await _edit(message);
    } else if (action == 'delete') {
      await _delete(message);
    } else if (action == 'profile') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserProfileScreen(uid: message.senderId!),
      ));
    }
  }

  void _toggleReaction(Message message, String emoji) {
    _services.chats
        .toggleReaction(message, _session.uid, emoji)
        .catchError((_) => _toast('Could not update the reaction.'));
  }

  void _showReactions(Message message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final palette = MessengerPalette.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 14),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Reactions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
              ),
              for (final entry in message.reactions.entries)
                if (entry.key.startsWith(OrbitImportSink.externalReactorPrefix))
                  _externalReactor(entry.key, entry.value)
                else
                  UserProfileBuilder(
                    uid: entry.key,
                    builder: (context, profile) => ListTile(
                      leading: AvatarBubble(
                        name: profile?.displayName ?? entry.key,
                        photoUrl: profile?.photoUrl,
                        seed: entry.key,
                        size: 36,
                      ),
                      title: Text(entry.key == _session.uid
                          ? 'You'
                          : profile?.displayName ?? 'Someone'),
                      trailing: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Current name of an imported sender, so renamed contacts show up on old
  /// messages too.
  static String? _participantName(Conversation c, String? address) {
    if (address == null) return null;
    final key = normalizeAddress(address);
    for (final p in c.externalParticipants) {
      if (p.displayName.trim().isNotEmpty && normalizeAddress(p.address) == key) {
        return p.displayName;
      }
    }
    return null;
  }

  Widget _externalReactor(String key, String emoji) {
    final address =
        key.substring(OrbitImportSink.externalReactorPrefix.length);
    final person = _conversation?.externalParticipants
        .where((p) => p.address == address)
        .firstOrNull;
    final label = person?.label ?? address;
    return ListTile(
      leading: AvatarBubble(name: label, seed: address, size: 36),
      title: Text(label),
      trailing: Text(emoji, style: const TextStyle(fontSize: 22)),
    );
  }

  Future<void> _edit(Message message) async {
    final controller = TextEditingController(text: message.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty || result == message.text) {
      return;
    }
    _services.chats
        .editMessage(
          conversationId: message.conversationId,
          messageId: message.id,
          text: result,
        )
        .catchError((_) => _toast('Could not edit the message.'));
  }

  Future<void> _delete(Message message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final palette = MessengerPalette.of(context);
        return AlertDialog(
          title: const Text('Delete for everyone?'),
          content: const Text(
              'Everyone in this chat will see that a message was deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: palette.danger,
                minimumSize: const Size(76, 44),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final attachments = message.attachments;
    _services.chats
        .deleteForEveryone(
          conversationId: message.conversationId,
          messageId: message.id,
        )
        .then((_) => _services.media.deleteAttachments(attachments))
        .catchError((_) => _toast('Could not delete the message.'));
  }

  // UI

  PreferredSizeWidget _appBar(Conversation c) {
    final otherUid = c.otherMemberId(_session.uid);
    Widget title;
    VoidCallback? onTap;
    if (otherUid != null) {
      onTap = () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => UserProfileScreen(uid: otherUid),
          ));
      title = UserProfileBuilder(
        uid: otherUid,
        builder: (context, profile) => _HeaderTitle(
          avatar: AvatarBubble(
            name: profile?.displayName ?? '',
            photoUrl: profile?.photoUrl,
            seed: otherUid,
            size: 34,
            online: profile?.isOnlineAt(DateTime.now()) ?? false,
          ),
          title: profile?.displayName ?? '…',
          subtitle:
              profile == null ? '' : presenceLabel(profile, DateTime.now()),
        ),
      );
    } else {
      final name = fallbackConversationTitle(c);
      if (c.isGroup) {
        onTap = () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupInfoScreen(conversationId: c.id),
            ));
      }
      title = _HeaderTitle(
        avatar: AvatarBubble(
          name: name,
          photoUrl: c.photoUrl,
          seed: c.id,
          size: 34,
          icon: c.isGroup ? Icons.group_rounded : null,
        ),
        title: name,
        subtitle: c.isGroup
            ? '${c.memberIds.length} members'
            : c.importSource != null
                ? 'Imported history'
                : '',
      );
    }
    return AppBar(
      titleSpacing: 0,
      title: Semantics(
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: title,
          ),
        ),
      ),
      actions: [
        if (c.isGroup)
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Group info',
            onPressed: onTap,
            icon: const Icon(Icons.info_outline_rounded),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final c = _conversation;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _conversationMissing
              ? Text(
                  'This conversation is not available.',
                  style: TextStyle(color: palette.secondaryInk, fontSize: 14),
                )
              : const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
        ),
      );
    }
    final isMember = c.memberIds.contains(_session.uid);

    return Scaffold(
      appBar: _appBar(c),
      body: Column(
        children: [
          Expanded(child: _messageList(c, palette)),
          for (final upload in _uploads)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.hairline)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: palette.secondaryInk,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sending ${upload.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: palette.secondaryInk,
                          ),
                        ),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          minHeight: 2.5,
                          backgroundColor: palette.hairline,
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(2),
                          value: upload.progress == 0 ? null : upload.progress,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (isMember)
            _composer(palette)
          else
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.hairline)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'You are no longer a member of this group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.secondaryInk,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _messageList(Conversation c, MessengerPalette palette) {
    if (_messagesError != null) {
      return Center(
        child: Text(
          _messagesError!,
          style: TextStyle(color: palette.secondaryInk, fontSize: 14),
        ),
      );
    }
    if (!_messagesLoaded) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No messages yet',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Say hello below to start the conversation.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.secondaryInk,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final entries = buildTimeline(_messages).reversed.toList();
    final now = DateTime.now();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _hasMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Start of conversation',
                      style: TextStyle(
                        color: palette.mutedInk,
                        fontSize: 12,
                      ),
                    ),
            ),
          );
        }
        final entry = entries[index];
        switch (entry) {
          case DaySeparatorEntry(:final day):
            return _DaySeparator(label: daySeparatorLabel(day, now));
          case MessageEntry(:final message, :final showSender):
            final mine = message.isFrom(_session.uid);
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: MessageBubble(
                key: ValueKey(message.id),
                message: message,
                mine: mine,
                myUid: _session.uid,
                showSender:
                    showSender && (c.isGroup || c.importSource != null),
                senderLabel: _participantName(c, message.senderAddress),
                onOpenActions: () => _openActions(message),
                onToggleReaction: (emoji) => _toggleReaction(message, emoji),
                onShowReactions: () => _showReactions(message),
              ),
            );
        }
      },
    );
  }

  Widget _composer(MessengerPalette palette) {
    final pillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: palette.hairline),
    );
    final focusedPillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: palette.accent, width: 1.2),
    );

    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: _recording
              ? Row(
                  children: [
                    IconButton(
                      tooltip: 'Discard recording',
                      onPressed: () => _finishRecording(send: false),
                      style: IconButton.styleFrom(
                        foregroundColor: palette.secondaryInk,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.fiber_manual_record,
                      color: palette.danger,
                      size: 12,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recording ${formatDuration(_recordElapsed)}',
                        semanticsLabel: 'Recording voice message',
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Send voice message',
                      onPressed: () => _finishRecording(send: true),
                      style: IconButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 22),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PopupMenuButton<_Attach>(
                      tooltip: 'Attach',
                      style: IconButton.styleFrom(
                        foregroundColor: palette.secondaryInk,
                        minimumSize: const Size(44, 44),
                      ),
                      icon: Icon(
                        Icons.add_rounded,
                        size: 24,
                        color: palette.secondaryInk,
                      ),
                      onSelected: _attach,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _Attach.photo,
                          child: _MenuRow(Icons.photo_outlined, 'Photo'),
                        ),
                        if (PlatformCaps.camera)
                          const PopupMenuItem(
                            value: _Attach.camera,
                            child:
                                _MenuRow(Icons.photo_camera_outlined, 'Camera'),
                          ),
                        const PopupMenuItem(
                          value: _Attach.video,
                          child: _MenuRow(Icons.movie_outlined, 'Video'),
                        ),
                        const PopupMenuItem(
                          value: _Attach.document,
                          child:
                              _MenuRow(Icons.description_outlined, 'Document'),
                        ),
                        const PopupMenuItem(
                          value: _Attach.gif,
                          child: _MenuRow(Icons.gif_box_outlined, 'GIF'),
                        ),
                        const PopupMenuItem(
                          value: _Attach.sticker,
                          child: _MenuRow(
                              Icons.emoji_emotions_outlined, 'Sticker'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          fontSize: 15,
                          color: palette.ink,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          isDense: true,
                          filled: true,
                          fillColor: palette.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: pillBorder,
                          enabledBorder: pillBorder,
                          focusedBorder: focusedPillBorder,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _text,
                      builder: (context, value, _) {
                        final hasText = value.text.trim().isNotEmpty;
                        if (hasText) {
                          return IconButton.filled(
                            tooltip: 'Send',
                            onPressed: _sendText,
                            style: IconButton.styleFrom(
                              backgroundColor: palette.accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(44, 44),
                            ),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 22,
                            ),
                          );
                        }
                        return IconButton.filled(
                          tooltip: 'Record voice message',
                          onPressed: _startRecording,
                          style: IconButton.styleFrom(
                            backgroundColor: palette.surface,
                            foregroundColor: palette.secondaryInk,
                            minimumSize: const Size(44, 44),
                          ),
                          icon: const Icon(Icons.mic_none_rounded, size: 22),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: palette.secondaryInk),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: palette.ink, fontSize: 14.5),
        ),
      ],
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.avatar,
    required this.title,
    required this.subtitle,
  });

  final Widget avatar;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                  letterSpacing: -0.15,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.secondaryInk,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: palette.mutedInk,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
