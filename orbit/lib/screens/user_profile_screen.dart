import 'package:flutter/material.dart';

import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/user_profile_builder.dart';

/// Read-only profile of another Orbit user.
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return UserProfileBuilder(
      uid: uid,
      builder: (context, profile) {
        return Scaffold(
          appBar: AppBar(title: const Text('Contact info')),
          body: profile == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: AvatarBubble(
                        name: profile.displayName,
                        photoUrl: profile.photoUrl,
                        seed: uid,
                        size: 112,
                        online: profile.isOnlineAt(DateTime.now()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile.displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      presenceLabel(profile, DateTime.now()),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: OrbitColors.soft),
                    ),
                    const SizedBox(height: 24),
                    if (profile.about.isNotEmpty)
                      _Field(label: 'About', value: profile.about),
                    _Field(label: 'Email', value: profile.email),
                    if (profile.phone.isNotEmpty)
                      _Field(label: 'Phone', value: profile.phone),
                  ],
                ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: OrbitColors.soft)),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}
