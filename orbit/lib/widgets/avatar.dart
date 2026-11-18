import 'package:flutter/material.dart';

import '../theme/orbit_theme.dart';
import 'net_image.dart';
import 'user_profile_builder.dart';

/// Circle avatar showing a photo when available, otherwise initials or [icon]
/// on a calm neutral surface from [MessengerPalette].
class AvatarBubble extends StatelessWidget {
  const AvatarBubble({
    super.key,
    required this.name,
    this.photoUrl,
    this.seed,
    this.size = 44,
    this.online = false,
    this.icon,
  });

  final String name;
  final String? photoUrl;
  final String? seed;
  final double size;
  final bool online;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final initials = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final url = photoUrl;

    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.avatarFill,
        shape: BoxShape.circle,
      ),
      child: url != null && url.isNotEmpty
          ? NetImage(url, width: size, height: size)
          : icon != null
              ? Icon(icon, color: palette.avatarInk, size: size * 0.48)
              : Text(
                  initials.isEmpty ? '?' : initials,
                  style: TextStyle(
                    color: palette.avatarInk,
                    fontWeight: FontWeight.w600,
                    fontSize: size * 0.36,
                    letterSpacing: -0.2,
                    height: 1,
                  ),
                ),
    );

    final dot = size * 0.28;
    return Semantics(
      label: online ? '$name, online' : name,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            circle,
            if (online)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: palette.online,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Avatar for an Orbit user, kept live from their profile.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.uid,
    this.size = 44,
    this.showPresence = false,
    this.fallbackName = '',
  });

  final String uid;
  final double size;
  final bool showPresence;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return UserProfileBuilder(
      uid: uid,
      builder: (context, profile) {
        return AvatarBubble(
          name: profile?.displayName ?? fallbackName,
          photoUrl: profile?.photoUrl,
          seed: uid,
          size: size,
          online: showPresence && (profile?.isOnlineAt(DateTime.now()) ?? false),
        );
      },
    );
  }
}
