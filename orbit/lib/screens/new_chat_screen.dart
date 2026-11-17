import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../widgets/user_search.dart';
import 'chat_screen.dart';
import 'new_group_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  bool _opening = false;

  Future<void> _open(UserProfile user) async {
    if (_opening) return;
    setState(() => _opening = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conversation =
          await context.read<OrbitServices>().chats.openDirectChat(
                myUid: context.read<Session>().uid,
                otherUid: user.uid,
              );
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conversation.id),
      ));
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the chat. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: UserSearch(
        onSelect: _open,
        header: ListTile(
          minTileHeight: 56,
          leading: const CircleAvatar(
            backgroundColor: OrbitColors.raised,
            child: Icon(Icons.group_add_rounded, color: OrbitColors.accent),
          ),
          title: const Text('New group'),
          onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => const NewGroupScreen(),
          )),
        ),
      ),
    );
  }
}
