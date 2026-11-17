import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/user_profile_builder.dart';
import '../widgets/user_search.dart';
import 'user_profile_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final Stream<Conversation?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = context
        .read<OrbitServices>()
        .chats
        .watchConversation(widget.conversationId);
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _rename(Conversation c) async {
    final controller = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await context.read<OrbitServices>().chats.renameGroup(c.id, name);
    } catch (_) {
      _toast('Could not rename the group.');
    }
  }

  Future<void> _addMembers(Conversation c) async {
    final chats = context.read<OrbitServices>().chats;
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _AddMembersScreen(existing: c.memberIds.toSet()),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      await chats.addMembers(c.id, picked);
    } catch (_) {
      _toast('Could not add members.');
    }
  }

  Future<void> _remove(Conversation c, String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('They will no longer see new messages.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<OrbitServices>().chats.removeMember(c.id, uid);
    } catch (_) {
      _toast('Could not remove that member.');
    }
  }

  Future<void> _leave(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You will stop receiving messages from this group.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48)),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await context
          .read<OrbitServices>()
          .chats
          .leaveGroup(c.id, context.read<Session>().uid);
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {
      _toast('Could not leave the group.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = context.watch<Session>().uid;
    return StreamBuilder<Conversation?>(
      stream: _stream,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group info')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final admin = c.isAdmin(myUid);
        final member = c.memberIds.contains(myUid);
        return Scaffold(
          appBar: AppBar(title: const Text('Group info')),
          body: ListView(
            children: [
              const SizedBox(height: 16),
              Center(
                child: AvatarBubble(
                  name: c.name,
                  photoUrl: c.photoUrl,
                  seed: c.id,
                  size: 88,
                  icon: Icons.group_rounded,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  c.name.isEmpty ? 'Group' : c.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Center(
                child: Text('${c.memberIds.length} members',
                    style: const TextStyle(color: OrbitColors.soft)),
              ),
              const SizedBox(height: 12),
              if (admin) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Rename group'),
                  onTap: () => _rename(c),
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: const Text('Add members'),
                  onTap: () => _addMembers(c),
                ),
              ],
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Members',
                    style: TextStyle(
                        color: OrbitColors.soft, fontWeight: FontWeight.w600)),
              ),
              for (final uid in c.memberIds)
                UserProfileBuilder(
                  key: ValueKey(uid),
                  uid: uid,
                  builder: (context, profile) {
                    final name = profile?.displayName ?? '…';
                    return ListTile(
                      minTileHeight: 56,
                      leading: AvatarBubble(
                        name: name,
                        photoUrl: profile?.photoUrl,
                        seed: uid,
                        online: profile?.isOnlineAt(DateTime.now()) ?? false,
                      ),
                      title: Text(uid == myUid ? '$name (you)' : name),
                      subtitle: profile == null
                          ? null
                          : Text(presenceLabel(profile, DateTime.now()),
                              style: const TextStyle(color: OrbitColors.soft)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (c.isAdmin(uid))
                            const Text('Admin',
                                style: TextStyle(
                                    color: OrbitColors.accent, fontSize: 12)),
                          if (admin && uid != myUid)
                            IconButton(
                              tooltip: 'Remove $name',
                              onPressed: () => _remove(c, uid, name),
                              icon: const Icon(
                                  Icons.remove_circle_outline_rounded),
                            ),
                        ],
                      ),
                      onTap: uid == myUid
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => UserProfileScreen(uid: uid),
                              )),
                    );
                  },
                ),
              const SizedBox(height: 16),
              if (member)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: () => _leave(c),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: const Color(0xFFFB7185),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Leave group'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AddMembersScreen extends StatefulWidget {
  const _AddMembersScreen({required this.existing});

  final Set<String> existing;

  @override
  State<_AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<_AddMembersScreen> {
  final Map<String, UserProfile> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add members'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selected.keys.toList()),
              style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
              child: Text(
                  _selected.isEmpty ? 'Add' : 'Add ${_selected.length}'),
            ),
          ),
        ],
      ),
      body: UserSearch(
        excludeIds: widget.existing,
        selectedIds: _selected.keys.toSet(),
        onSelect: (user) => setState(() {
          if (_selected.remove(user.uid) == null) _selected[user.uid] = user;
        }),
      ),
    );
  }
}
