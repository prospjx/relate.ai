import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../services/sms_sync.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/user_profile_builder.dart';
import 'chat_screen.dart';
import 'import_entry_web.dart' if (dart.library.io) 'import_entry_io.dart';
import 'new_chat_screen.dart';
import 'profile_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final Stream<List<Conversation>> _inbox;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _inbox = context.read<OrbitServices>().chats.watchInbox(session.uid);
  }

  void _openNewMessage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final session = context.watch<Session>();
    final me = session.me;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (importSupported)
            IconButton(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Import chats from your phone',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: buildImportScreen,
              )),
              icon: const Icon(Icons.download_rounded),
            ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'New message',
            onPressed: () => _openNewMessage(context),
            icon: Icon(Icons.edit_square, color: palette.accent),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Profile and settings',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProfileScreen(),
              )),
              icon: AvatarBubble(
                name: session.displayName,
                photoUrl: me?.photoUrl,
                seed: session.uid,
                size: 30,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _SmsSyncStrip(),
          Expanded(child: _conversationList(session, palette)),
        ],
      ),
    );
  }

  Widget _conversationList(Session session, MessengerPalette palette) {
    return StreamBuilder<List<Conversation>>(
      stream: _inbox,
      builder: (context, snap) {
        if (snap.hasError) {
          return _InboxMessage(
            icon: Icons.error_outline_rounded,
            isError: true,
            title: 'Could not load messages',
            body: '${snap.error}',
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          );
        }
        // Imported chats appear once their messages are saved.
        final conversations = [
          for (final c in snap.data!)
            if (c.importSource == null || c.lastMessage != null) c,
        ];
        if (conversations.isEmpty) {
          return _InboxMessage(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'No messages yet',
            body: importSupported
                ? 'Start a conversation by name or email, or import existing texts from your phone.'
                : 'Start a conversation with someone by name or email.',
            actionLabel: 'New message',
            onAction: () => _openNewMessage(context),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: conversations.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            indent: 76,
            color: palette.hairline,
          ),
          itemBuilder: (context, index) => ConversationTile(
            key: ValueKey(conversations[index].id),
            conversation: conversations[index],
            myUid: session.uid,
          ),
        );
      },
    );
  }
}

/// On Android: offers to turn on text sync, and shows progress while it runs.
class _SmsSyncStrip extends StatefulWidget {
  const _SmsSyncStrip();

  @override
  State<_SmsSyncStrip> createState() => _SmsSyncStripState();
}

class _SmsSyncStripState extends State<_SmsSyncStrip> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SmsSync?>();
    if (sync == null || !sync.supported) return const SizedBox.shrink();
    final palette = MessengerPalette.of(context);

    if (sync.enabled) {
      if (sync.syncing) return _SyncProgress(sync: sync);
      final error = sync.error;
      if (error == null) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          children: [
            Icon(Icons.sync_problem_rounded, size: 20, color: palette.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(
              onPressed: sync.syncNow,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 44),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_dismissed) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sync texts from this phone',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Keep your phone texts in sync across your devices.',
            style: TextStyle(
              color: palette.secondaryInk,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 6),
            Text(
              sync.error!,
              style: TextStyle(
                color: palette.danger,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _dismissed = true),
                style: TextButton.styleFrom(
                  foregroundColor: palette.secondaryInk,
                  minimumSize: const Size(64, 36),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('Not now'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: sync.enable,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(76, 36),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Turn on'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncProgress extends StatelessWidget {
  const _SyncProgress({required this.sync});

  final SmsSync sync;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final total = sync.progressTotal;
    final done = sync.progressDone.clamp(0, total);
    final number = NumberFormat.decimalPattern();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total > 0
                ? 'Syncing texts… ${number.format(done)} of ${number.format(total)}'
                : 'Syncing texts…',
            style: TextStyle(
              color: palette.secondaryInk,
              fontSize: 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            minHeight: 2.5,
            backgroundColor: palette.hairline,
            color: palette.accent,
            borderRadius: BorderRadius.circular(2),
            value: total > 0 ? done / total : null,
          ),
        ],
      ),
    );
  }
}

class _InboxMessage extends StatelessWidget {
  const _InboxMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 32,
                color: isError ? palette.danger : palette.mutedInk,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: palette.secondaryInk,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Title for a conversation that has no other Orbit member to name it.
String fallbackConversationTitle(Conversation c) {
  if (c.name.trim().isNotEmpty) return c.name;
  if (c.externalParticipants.isNotEmpty) {
    return c.externalParticipants.map((p) => p.label).join(', ');
  }
  return c.isGroup ? 'Group' : 'Note to self';
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.myUid,
  });

  final Conversation conversation;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    final otherUid = conversation.otherMemberId(myUid);
    if (otherUid == null) {
      final title = fallbackConversationTitle(conversation);
      return _tile(
        context,
        title: title,
        avatar: AvatarBubble(
          name: title,
          photoUrl: conversation.photoUrl,
          seed: conversation.id,
          size: 48,
          icon: conversation.isGroup ? Icons.group_rounded : null,
        ),
      );
    }
    return UserProfileBuilder(
      uid: otherUid,
      builder: (context, profile) {
        final name = profile?.displayName ?? '…';
        return _tile(
          context,
          title: name,
          avatar: AvatarBubble(
            name: name,
            photoUrl: profile?.photoUrl,
            seed: otherUid,
            size: 48,
            online: profile?.isOnlineAt(DateTime.now()) ?? false,
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required Widget avatar,
  }) {
    final palette = MessengerPalette.of(context);
    final last = conversation.lastMessage;
    final unread = conversation.hasUnreadFor(myUid);
    var preview = last?.preview ?? 'No messages yet';
    if (last != null &&
        conversation.isGroup &&
        last.kind != MessageKind.system) {
      final who = last.senderId == myUid ? 'You' : last.senderName;
      if (who.isNotEmpty) preview = '$who: $preview';
    } else if (last != null && last.senderId == myUid) {
      preview = 'You: $preview';
    }
    final when = inboxTimeLabel(
      last?.sentAt ?? conversation.updatedAt,
      DateTime.now(),
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      horizontalTitleGap: 12,
      minVerticalPadding: 10,
      leading: avatar,
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                color: palette.ink,
                letterSpacing: -0.15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            when,
            style: TextStyle(
              color: palette.mutedInk,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: unread ? palette.ink : palette.secondaryInk,
                  fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                  height: 1.3,
                ),
              ),
            ),
            if (unread)
              Semantics(
                label: 'Unread',
                child: Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conversation.id),
      )),
    );
  }
}
