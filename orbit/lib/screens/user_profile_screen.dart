import 'package:flutter/material.dart';

import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/user_profile_builder.dart';

/// Read-only profile of another user.
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    return UserProfileBuilder(
      uid: uid,
      builder: (context, profile) {
        final fields = <(String, String)>[
          if (profile != null && profile.about.isNotEmpty)
            ('About', profile.about),
          if (profile != null && profile.email.isNotEmpty)
            ('Email', profile.email),
          if (profile != null && profile.phone.isNotEmpty)
            ('Phone', profile.phone),
        ];

        return Scaffold(
          appBar: AppBar(title: const Text('Contact info')),
          body: profile == null
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Center(
                          child: AvatarBubble(
                            name: profile.displayName,
                            photoUrl: profile.photoUrl,
                            seed: uid,
                            size: 96,
                            online: profile.isOnlineAt(DateTime.now()),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          profile.displayName,
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
                        const SizedBox(height: 4),
                        Text(
                          presenceLabel(profile, DateTime.now()),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.secondaryInk,
                            fontSize: 14,
                          ),
                        ),
                        if (fields.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Container(
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: palette.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < fields.length; i++) ...[
                                  if (i > 0)
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      indent: 16,
                                      color: palette.hairline,
                                    ),
                                  _Field(
                                    label: fields[i].$1,
                                    value: fields[i].$2,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
    final palette = MessengerPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: palette.secondaryInk,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 15,
              color: palette.ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
