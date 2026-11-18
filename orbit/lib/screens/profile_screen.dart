import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../services/file_pick.dart';
import '../services/platform_caps.dart';
import '../services/sms_sync.dart';
import '../state/session.dart';
import '../theme/orbit_theme.dart';
import '../widgets/avatar.dart';

/// Edit your own profile and sign out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  final _phone = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Display name is required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<OrbitServices>().users.updateProfile(
            context.read<Session>().uid,
            displayName: _name.text,
            about: _about.text,
            phone: _phone.text,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save your profile.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto({bool camera = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final services = context.read<OrbitServices>();
    final uid = context.read<Session>().uid;
    final picked =
        camera ? await takePhoto() : await pickFile(type: FileType.image);
    if (picked == null) return;
    if (!picked.mimeType.startsWith('image/')) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Choose an image file.')));
      return;
    }
    setState(() => _uploading = true);
    try {
      final url = await services.media.uploadAvatar(
        uid: uid,
        bytes: picked.bytes,
        mimeType: picked.mimeType,
      );
      await services.users.updateProfile(uid, photoUrl: url);
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}.')));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not upload the photo.')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    final session = context.read<Session>();
    await context
        .read<OrbitServices>()
        .users
        .updateProfile(session.uid, clearPhoto: true);
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await context.read<OrbitServices>().auth.signOut();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final session = context.watch<Session>();
    final me = session.me;
    if (!_loaded && me != null) {
      _name.text = me.displayName;
      _about.text = me.about;
      _phone.text = me.phone;
      _loaded = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AvatarBubble(
                      name: session.displayName,
                      photoUrl: me?.photoUrl,
                      seed: session.uid,
                      size: 104,
                    ),
                    if (_uploading)
                      const SizedBox(
                        width: 104,
                        height: 104,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: _uploading ? null : () => _changePhoto(),
                    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('Choose photo'),
                  ),
                  if (PlatformCaps.camera)
                    TextButton.icon(
                      onPressed:
                          _uploading ? null : () => _changePhoto(camera: true),
                      style:
                          TextButton.styleFrom(minimumSize: const Size(44, 44)),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Take photo'),
                    ),
                  if (me?.photoUrl != null)
                    TextButton(
                      onPressed: _uploading ? null : _removePhoto,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.danger,
                        minimumSize: const Size(44, 44),
                      ),
                      child: const Text('Remove'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Display name',
                  counterStyle:
                      TextStyle(color: palette.mutedInk, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _about,
                maxLength: 280,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: 'About',
                  hintText: 'A short status, like "At work" or "Available"',
                  counterStyle:
                      TextStyle(color: palette.mutedInk, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.secondaryInk,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      session.email,
                      style: TextStyle(color: palette.ink, fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_saving ? 'Saving…' : 'Save profile'),
              ),
              const _SmsSyncSettings(),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.danger,
                  side: BorderSide(
                    color: palette.danger.withValues(alpha: 0.35),
                  ),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmsSyncSettings extends StatelessWidget {
  const _SmsSyncSettings();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SmsSync?>();
    if (sync == null || !sync.supported) return const SizedBox.shrink();
    final palette = MessengerPalette.of(context);
    final last = sync.lastSyncedAt;
    final number = NumberFormat.decimalPattern();
    final status = sync.syncing
        ? (sync.progressTotal > 0
            ? 'Syncing… ${number.format(sync.progressDone.clamp(0, sync.progressTotal))} '
                'of ${number.format(sync.progressTotal)} texts'
            : 'Syncing…')
        : sync.error ??
            (last == null
                ? 'Copies the texts on this phone and keeps them up to date.'
                : 'Last synced ${DateFormat.yMMMd().add_jm().format(last)}');
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, thickness: 1, color: palette.hairline),
          const SizedBox(height: 20),
          Text(
            'Text messages',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.secondaryInk,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.hairline),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: Text(
                    'Sync texts from this phone',
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      color: sync.error != null
                          ? palette.danger
                          : palette.secondaryInk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  value: sync.enabled,
                  onChanged: (on) => on ? sync.enable() : sync.disable(),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 14,
                  color: palette.hairline,
                ),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  title: Text(
                    'Show contact names',
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    sync.contactsAllowed
                        ? '${NumberFormat.decimalPattern().format(sync.contacts.length)} numbers from your contacts'
                        : 'Names your chats from the contacts on this phone.',
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.secondaryInk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  value: sync.contactsAllowed,
                  onChanged:
                      sync.contactsAllowed ? null : (_) => sync.allowContacts(),
                ),
              ],
            ),
          ),
          if (sync.enabled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: sync.syncing ? null : sync.syncNow,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Sync now'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
