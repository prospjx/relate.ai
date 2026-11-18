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
      builder: (context) {
        final palette = MessengerPalette.of(context);
        return AlertDialog(
          title: Text('Remove $name?'),
          content: const Text('They will no longer see new messages.'),
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
                minimumSize: const Size(84, 44),
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
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
      builder: (context) {
        final palette = MessengerPalette.of(context);
        return AlertDialog(
          title: const Text('Leave group?'),
          content:
              const Text('You will stop receiving messages from this group.'),
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
              child: const Text('Leave'),
            ),
          ],
        );
      },
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
    final palette = MessengerPalette.of(context);
    final myUid = context.watch<Session>().uid;
    return StreamBuilder<Conversation?>(
      stream: _stream,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group info')),
            body: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        final admin = c.isAdmin(myUid);
        final member = c.memberIds.contains(myUid);
        return Scaffold(
          appBar: AppBar(title: const Text('Group info')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                children: [
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      c.name.isEmpty ? 'Group' : c.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                            letterSpacing: -0.3,
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '${c.memberIds.length} ${c.memberIds.length == 1 ? 'member' : 'members'}',
                      style: TextStyle(
                        color: palette.secondaryInk,
                        fontSize: 14,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (admin) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.hairline),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: palette.accent,
                                ),
                                title: Text(
                                  'Rename group',
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: palette.mutedInk,
                                ),
                                onTap: () => _rename(c),
                              ),
                              Divider(
                                height: 1,
                                thickness: 1,
                                indent: 52,
                                color: palette.hairline,
                              ),
                              ListTile(
                                leading: Icon(
                                  Icons.person_add_alt_1_outlined,
                                  size: 20,
                                  color: palette.accent,
                                ),
                                title: Text(
                                  'Add members',
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: palette.mutedInk,
                                ),
                                onTap: () => _addMembers(c),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Members',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.secondaryInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.hairline),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          children: [
                            for (var i = 0; i < c.memberIds.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 72,
                                  color: palette.hairline,
                                ),
                              UserProfileBuilder(
                                key: ValueKey(c.memberIds[i]),
                                uid: c.memberIds[i],
                                builder: (context, profile) {
                                  final uid = c.memberIds[i];
                                  final name = profile?.displayName ?? '…';
                                  return ListTile(
                                    minTileHeight: 56,
                                    horizontalTitleGap: 16,
                                    leading: AvatarBubble(
                                      name: name,
                                      photoUrl: profile?.photoUrl,
                                      seed: uid,
                                      size: 40,
                                      online:
                                          profile?.isOnlineAt(DateTime.now()) ??
                                              false,
                                    ),
                                    title: Text(
                                      uid == myUid ? '$name (you)' : name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.ink,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: profile == null
                                        ? null
                                        : Text(
                                            presenceLabel(
                                              profile,
                                              DateTime.now(),
                                            ),
                                            style: TextStyle(
                                              color: palette.secondaryInk,
                                              fontSize: 13,
                                            ),
                                          ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (c.isAdmin(uid))
                                          Text(
                                            'Admin',
                                            style: TextStyle(
                                              color: palette.secondaryInk,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        if (admin && uid != myUid)
                                          IconButton(
                                            constraints: const BoxConstraints(
                                              minWidth: 44,
                                              minHeight: 44,
                                            ),
                                            tooltip: 'Remove $name',
                                            onPressed: () =>
                                                _remove(c, uid, name),
                                            icon: Icon(
                                              Icons
                                                  .remove_circle_outline_rounded,
                                              color: palette.danger,
                                              size: 20,
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: uid == myUid
                                        ? null
                                        : () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    UserProfileScreen(uid: uid),
                                              ),
                                            ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (member)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _leave(c),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: palette.danger,
                          side: BorderSide(
                            color: palette.danger.withValues(alpha: 0.35),
                          ),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Leave group'),
                      ),
                    ),
                ],
              ),
            ),
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
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(
                _selected.isEmpty ? 'Add' : 'Add ${_selected.length}',
              ),
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
