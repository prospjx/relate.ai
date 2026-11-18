import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../services/sms_sync.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../widgets/phone_contacts_list.dart';
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conversation =
          await context.read<OrbitServices>().chats.openDirectChat(
                myUid: context.read<Session>().uid,
                otherUid: user.uid,
              );
      _openConversation(conversation.id);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the chat. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openConversation(String id) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChatScreen(conversationId: id),
    ));
  }

  Widget _peopleSearch(BuildContext context, {required bool autofocus}) {
    final palette = MessengerPalette.of(context);
    return UserSearch(
      onSelect: _open,
      autofocus: autofocus,
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            minTileHeight: 56,
            horizontalTitleGap: 16,
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: palette.avatarFill,
              child: Icon(
                Icons.group_add_rounded,
                size: 20,
                color: palette.accent,
              ),
            ),
            title: Text(
              'New group',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: palette.ink,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: palette.mutedInk,
            ),
            onTap: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const NewGroupScreen()),
            ),
          ),
          Divider(height: 1, thickness: 1, color: palette.hairline),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<SmsSync?>()?.supported ?? false;
    if (!phone) {
      return Scaffold(
        appBar: AppBar(title: const Text('New message')),
        body: _peopleSearch(context, autofocus: true),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New message'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Contacts'),
            Tab(text: 'People'),
          ]),
        ),
        body: TabBarView(children: [
          PhoneContactsList(onOpenConversation: _openConversation),
          _peopleSearch(context, autofocus: false),
        ]),
      ),
    );
  }
}
