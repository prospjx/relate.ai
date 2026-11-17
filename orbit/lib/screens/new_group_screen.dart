import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../widgets/avatar.dart';
import '../widgets/user_search.dart';
import 'chat_screen.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final Map<String, UserProfile> _selected = {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(UserProfile user) {
    setState(() {
      if (_selected.remove(user.uid) == null) _selected[user.uid] = user;
    });
  }

  Future<void> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Give the group a name.')));
      return;
    }
    if (_selected.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Add at least one member.')));
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final session = context.read<Session>();
    try {
      final conversation =
          await context.read<OrbitServices>().chats.createGroup(
                creatorUid: session.uid,
                creatorName: session.displayName,
                name: _name.text,
                memberIds: _selected.keys.toList(),
              );
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conversation.id),
      ));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not create the group.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _create,
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              child: Text(_saving ? 'Creating…' : 'Create'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final user in _selected.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        avatar: AvatarBubble(
                          name: user.displayName,
                          photoUrl: user.photoUrl,
                          seed: user.uid,
                          size: 24,
                        ),
                        label: Text(user.displayName),
                        onDeleted: () => _toggle(user),
                        deleteButtonTooltipMessage:
                            'Remove ${user.displayName}',
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: UserSearch(
              onSelect: _toggle,
              selectedIds: _selected.keys.toSet(),
              autofocus: false,
            ),
          ),
        ],
      ),
    );
  }
}
