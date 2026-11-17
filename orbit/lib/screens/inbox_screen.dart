import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final me = session.me;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (importSupported)
            IconButton(
              tooltip: 'Import chats from your phone',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: buildImportScreen,
              )),
              icon: const Icon(Icons.download_rounded),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Profile and settings',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProfileScreen(),
              )),
              icon: AvatarBubble(
                name: session.displayName,
                photoUrl: me?.photoUrl,
                seed: session.uid,
                size: 32,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const NewChatScreen(),
        )),
        icon: const Icon(Icons.edit_square),
        label: const Text('New chat'),
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: _inbox,
        builder: (context, snap) {
          if (snap.hasError) {
            return _InboxMessage(
              icon: Icons.error_outline_rounded,
              title: 'Could not load conversations',
              body: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final conversations = snap.data!;
          if (conversations.isEmpty) {
            return const _InboxMessage(
              icon: Icons.forum_outlined,
              title: 'No conversations yet',
              body: importSupported
                  ? 'Start a chat with someone by their email or name, '
                      'or import your old chats from your phone.'
                  : 'Start a chat with someone by their email or name.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: conversations.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 76, color: OrbitColors.line),
            itemBuilder: (context, index) => ConversationTile(
              key: ValueKey(conversations[index].id),
              conversation: conversations[index],
              myUid: session.uid,
            ),
          );
        },
      ),
    );
  }
}

class _InboxMessage extends StatelessWidget {
  const _InboxMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: OrbitColors.mute),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: OrbitColors.soft),
            ),
          ],
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
      return _tile(
        context,
        title: fallbackConversationTitle(conversation),
        avatar: AvatarBubble(
          name: fallbackConversationTitle(conversation),
          photoUrl: conversation.photoUrl,
          seed: conversation.id,
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
    final last = conversation.lastMessage;
    final unread = conversation.hasUnreadFor(myUid);
    var preview = last?.preview ?? 'No messages yet';
    if (last != null && conversation.isGroup && last.kind != MessageKind.system) {
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            when,
            style: TextStyle(
              color: unread ? OrbitColors.accent : OrbitColors.mute,
              fontSize: 12,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unread ? OrbitColors.ink : OrbitColors.soft,
              ),
            ),
          ),
          if (unread)
            Semantics(
              label: 'Unread',
              child: Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: OrbitColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conversation.id),
      )),
    );
  }
}
