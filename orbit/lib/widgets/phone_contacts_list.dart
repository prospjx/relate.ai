import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/chat_repository.dart';
import '../data/orbit_import_sink.dart';
import '../data/services.dart';
import '../import/util/address.dart';
import '../models/models.dart';
import '../models/phone_contact.dart';
import '../services/sms_sync.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import 'avatar.dart';

/// The phone's contacts. Tapping one opens the texts already imported for
/// that number, or an Orbit chat if they use Orbit, or offers an invite.
class PhoneContactsList extends StatefulWidget {
  const PhoneContactsList({super.key, required this.onOpenConversation});

  final void Function(String conversationId) onOpenConversation;

  @override
  State<PhoneContactsList> createState() => _PhoneContactsListState();
}

class _PhoneContactsListState extends State<PhoneContactsList> {
  final _query = TextEditingController();
  Map<String, UserProfile> _orbitUsers = const {};
  int _lookedUpCount = -1;
  bool _opening = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _findOrbitUsers(List<PhoneContact> contacts) async {
    if (contacts.length == _lookedUpCount) return;
    _lookedUpCount = contacts.length;
    try {
      final found = await context.read<OrbitServices>().users.findByPhones(
            contacts.map((c) => c.number),
            excludeUid: context.read<Session>().uid,
          );
      if (mounted) setState(() => _orbitUsers = found);
    } catch (_) {
      // Without the lookup every contact simply shows as not on Orbit.
    }
  }

  Future<void> _open(PhoneContact contact) async {
    if (_opening) return;
    setState(() => _opening = true);
    final services = context.read<OrbitServices>();
    final uid = context.read<Session>().uid;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final importedId = ChatRepository.importedConversationId(
        importerUid: uid,
        source: OrbitImportSink.source,
        externalKey: directThreadKey(contact.number),
      );
      final imported = await services.chats.getConversation(importedId);
      if (imported != null) {
        widget.onOpenConversation(imported.id);
        return;
      }
      final user = _orbitUsers[contact.normalizedNumber];
      if (user != null) {
        final chat = await services.chats.openDirectChat(myUid: uid, otherUid: user.uid);
        widget.onOpenConversation(chat.id);
        return;
      }
      if (mounted) await _offerInvite(contact);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open this contact. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _offerInvite(PhoneContact contact) async {
    final sync = context.read<SmsSync?>();
    final invite = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final palette = MessengerPalette.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${contact.name} isn\'t here yet',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You don\'t have any imported texts with them either. Send a text invite so you can chat here.',
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.secondaryInk,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('Invite by text'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (invite == true && sync != null) {
      await sync.inviteBySms(
        contact.number,
        'Hey ${contact.name.split(' ').first}, let\'s chat on Messages!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SmsSync?>();
    if (sync == null || !sync.supported) return const SizedBox.shrink();
    final palette = MessengerPalette.of(context);

    if (!sync.contactsAllowed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.contacts_outlined,
                  size: 32,
                  color: palette.mutedInk,
                ),
                const SizedBox(height: 12),
                Text(
                  'Show contact names',
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
                  'Match phone numbers to names from your contacts and see who you can message here. Contacts stay on this phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.secondaryInk,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: sync.allowContacts,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: const Text('Allow contacts'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final all = sync.contacts;
    if (all.isNotEmpty) _findOrbitUsers(all);
    final q = _query.text.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');
    final shown = q.isEmpty
        ? all
        : [
            for (final c in all)
              if (c.name.toLowerCase().contains(q) ||
                  (qDigits.isNotEmpty &&
                      c.number
                          .replaceAll(RegExp(r'[^0-9]'), '')
                          .contains(qDigits)))
                c,
          ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search contacts',
              isDense: true,
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: palette.mutedInk,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
        ),
        if (_opening)
          LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: palette.hairline,
            color: palette.accent,
          ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    all.isEmpty
                        ? 'No contacts with phone numbers.'
                        : 'No matches.',
                    style: TextStyle(color: palette.secondaryInk, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: shown.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    indent: 72,
                    color: palette.hairline,
                  ),
                  itemBuilder: (context, index) {
                    final contact = shown[index];
                    final available =
                        _orbitUsers.containsKey(contact.normalizedNumber);
                    return ListTile(
                      minTileHeight: 56,
                      horizontalTitleGap: 16,
                      leading: _ContactAvatar(contact: contact, sync: sync),
                      title: Text(
                        contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: palette.ink,
                        ),
                      ),
                      subtitle: Text(
                        contact.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.secondaryInk,
                          fontSize: 13.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      trailing: available
                          ? Text(
                              'Available',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.secondaryInk,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : null,
                      onTap: () => _open(contact),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.contact, required this.sync});

  final PhoneContact contact;
  final SmsSync sync;

  @override
  Widget build(BuildContext context) {
    final fallback = AvatarBubble(
      name: contact.name,
      seed: contact.normalizedNumber,
      size: 40,
    );
    if (contact.photoUri == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: sync.contactPhoto(contact),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return fallback;
        return CircleAvatar(radius: 20, backgroundImage: MemoryImage(bytes));
      },
    );
  }
}
