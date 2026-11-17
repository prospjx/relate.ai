import 'dart:typed_data';

import '../import/models.dart';
import '../import/sink.dart';
import '../models/models.dart';
import 'chat_repository.dart';

typedef ImportFileReader = Future<Uint8List> Function(String path);

typedef ImportUploader = Future<Attachment> Function({
  required String conversationId,
  required AttachmentKind kind,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
});

/// Writes imported phone history into Orbit conversations.
///
/// Every source shares one [source] id, so the same person imported from an
/// iPhone backup and from an Android export lands in one conversation.
/// A source message with several attachments becomes one Orbit message per
/// attachment (plus one for its text), because Orbit messages have one kind.
class OrbitImportSink extends ImportSink {
  OrbitImportSink({
    required this.chats,
    required this.importerUid,
    required this.importerName,
    required this.readFile,
    required this.upload,
  });

  static const source = 'phone';

  /// Reactions from people who aren't Orbit users are keyed by address with
  /// this prefix instead of a uid.
  static const externalReactorPrefix = 'ext:';

  static const _maxText = 8000;
  static const _maxGroupName = 80;

  final ChatRepository chats;
  final String importerUid;
  final String importerName;
  final ImportFileReader readFile;
  final ImportUploader upload;

  final Map<String, String> _conversationIds = {};
  final Map<String, Map<String, String>> _namesByThread = {};

  @override
  Future<void> upsertThread(ImportedThread thread) async {
    final participants = [
      for (final p in thread.participants)
        Participant(address: p.address, displayName: p.displayName ?? ''),
    ];
    final conversation = await chats.upsertImportedConversation(
      importerUid: importerUid,
      source: source,
      externalKey: thread.key,
      type: thread.isGroup ? ConversationType.group : ConversationType.direct,
      name: thread.isGroup ? _groupName(thread, participants) : '',
      participants: participants,
    );
    _conversationIds[thread.key] = conversation.id;
    _namesByThread[thread.key] = {
      for (final p in conversation.externalParticipants)
        if (p.displayName.isNotEmpty) p.address: p.displayName,
    };
  }

  @override
  Future<AppendResult> appendMessages(
    String threadKey,
    List<ImportedMessage> messages,
  ) async {
    final conversationId = _conversationIds[threadKey] ??
        ChatRepository.importedConversationId(
          importerUid: importerUid,
          source: source,
          externalKey: threadKey,
        );
    final names = _namesByThread[threadKey] ?? const {};

    final parts = <_Part>[
      for (final m in messages)
        if (m.kind != ImportedMessageKind.reaction) ..._partsOf(m),
    ];
    final existing = await chats.existingMessageIds(
      conversationId,
      [for (final p in parts) p.id],
    );
    final fresh = parts.where((p) => !existing.contains(p.id)).toList();

    final toWrite = <Message>[];
    for (final part in fresh) {
      toWrite.add(await _toMessage(part, conversationId, names));
    }
    await chats.importMessages(
      conversationId: conversationId,
      importerUid: importerUid,
      source: source,
      messages: toWrite,
      skipExisting: false,
    );

    final reactions = <String, Map<String, String?>>{};
    for (final m in messages) {
      final target = m.reactionTargetKey;
      if (m.kind != ImportedMessageKind.reaction || target == null) continue;
      final reactor = m.isFromMe
          ? importerUid
          : '$externalReactorPrefix${m.senderAddress ?? 'unknown'}';
      final emoji = m.reactionRemoved ? null : m.reaction;
      reactions.putIfAbsent(
        ChatRepository.importedMessageId(source: source, importKey: target),
        () => {},
      )[reactor] = emoji;
    }
    final reacted = await chats.applyImportedReactions(
      conversationId: conversationId,
      byMessageId: reactions,
    );

    final newKeys = {for (final p in fresh) p.message.key};
    final reactionCount =
        messages.where((m) => m.kind == ImportedMessageKind.reaction).length;
    final normalCount = messages.length - reactionCount;
    return AppendResult(
      inserted: newKeys.length + reacted,
      skipped: (normalCount - newKeys.length) + (reactionCount - reacted),
    );
  }

  List<_Part> _partsOf(ImportedMessage m) {
    final available = [
      for (final a in m.attachments)
        if (a.isAvailable && a.localPath != null) a,
    ];
    final notes = [
      for (final a in m.attachments)
        if (!a.isAvailable || a.localPath == null)
          '[Attachment not recovered: ${a.fileName}]',
    ];
    final text = [
      if (m.subject?.trim().isNotEmpty ?? false) m.subject!.trim(),
      if (m.text.trim().isNotEmpty) m.text,
      ...notes,
    ].join('\n');

    final parts = <_Part>[];
    if (text.isNotEmpty) {
      parts.add(_Part(_id(m.key), m.key, m, text: text));
    }
    for (var i = 0; i < available.length; i++) {
      final key = parts.isEmpty && i == 0 ? m.key : '${m.key}#$i';
      parts.add(_Part(_id(key), key, m, attachment: available[i]));
    }
    return parts;
  }

  Future<Message> _toMessage(
    _Part part,
    String conversationId,
    Map<String, String> names,
  ) async {
    final m = part.message;
    var kind = m.kind == ImportedMessageKind.system
        ? MessageKind.system
        : MessageKind.text;
    var text = part.text;
    final attachments = <Attachment>[];
    final a = part.attachment;
    if (a != null) {
      final attachmentKind = _attachmentKind(a.mimeType);
      try {
        final bytes = await readFile(a.localPath!);
        attachments.add(await upload(
          conversationId: conversationId,
          kind: attachmentKind,
          bytes: bytes,
          fileName: a.fileName,
          mimeType: a.mimeType,
        ));
        kind = MessageKind.values.byName(attachmentKind.name);
      } catch (_) {
        text = '[Attachment could not be copied: ${a.fileName}]';
      }
    }
    final address = m.senderAddress;
    return Message(
      id: part.id,
      conversationId: conversationId,
      kind: kind,
      sentAt: m.sentAt,
      senderId: m.isFromMe ? importerUid : null,
      senderAddress: m.isFromMe ? null : address,
      senderName: m.isFromMe ? importerName : (names[address] ?? ''),
      text: text.length > _maxText ? text.substring(0, _maxText) : text,
      attachments: attachments,
      importKey: part.key,
    );
  }

  String _id(String key) =>
      ChatRepository.importedMessageId(source: source, importKey: key);

  static String _groupName(ImportedThread thread, List<Participant> people) {
    final title = thread.title?.trim() ?? '';
    final name = title.isNotEmpty
        ? title
        : people.isEmpty
            ? 'Imported group'
            : people.map((p) => p.label).join(', ');
    return name.length > _maxGroupName
        ? '${name.substring(0, _maxGroupName - 1)}…'
        : name;
  }

  static AttachmentKind _attachmentKind(String mimeType) {
    final mime = mimeType.toLowerCase();
    if (mime == 'image/gif') return AttachmentKind.gif;
    if (mime.startsWith('image/')) return AttachmentKind.image;
    if (mime.startsWith('video/')) return AttachmentKind.video;
    if (mime.startsWith('audio/')) return AttachmentKind.audio;
    return AttachmentKind.document;
  }
}

class _Part {
  _Part(this.id, this.key, this.message, {this.text = '', this.attachment});

  final String id;
  final String key;
  final ImportedMessage message;
  final String text;
  final ImportedAttachment? attachment;
}
