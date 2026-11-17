import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/services.dart';
import '../services/file_pick.dart';
import '../services/platform_caps.dart';
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
      body: ListView(
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
                  size: 112,
                ),
                if (_uploading)
                  const SizedBox(
                    width: 112,
                    height: 112,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _uploading ? null : () => _changePhoto(),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Choose photo'),
              ),
              if (PlatformCaps.camera)
                TextButton.icon(
                  onPressed:
                      _uploading ? null : () => _changePhoto(camera: true),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take photo'),
                ),
              if (me?.photoUrl != null)
                TextButton(
                  onPressed: _uploading ? null : _removePhoto,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _about,
            maxLength: 280,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'About',
              hintText: 'A short status, like "At work" or "Available"',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 16),
          Text('Email', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(session.email, style: const TextStyle(color: OrbitColors.soft)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: Text(_saving ? 'Saving…' : 'Save profile'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
