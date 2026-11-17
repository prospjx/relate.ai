import 'codec.dart';

/// Public profile stored at `users/{uid}`.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.email = '',
    this.about = '',
    this.phone = '',
    this.photoUrl,
    this.online = false,
    this.lastSeen,
    this.createdAt,
  });

  /// A heartbeat older than this means the user is treated as offline even if
  /// the app never got the chance to write `online: false`.
  static const presenceTimeout = Duration(minutes: 2);

  final String uid;
  final String displayName;
  final String email;
  final String about;
  final String phone;
  final String? photoUrl;
  final bool online;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  bool isOnlineAt(DateTime now) {
    if (!online || lastSeen == null) return false;
    return now.difference(lastSeen!) <= presenceTimeout;
  }

  UserProfile copyWith({
    String? displayName,
    String? about,
    String? phone,
    String? photoUrl,
    bool clearPhoto = false,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email,
      about: about ?? this.about,
      phone: phone ?? this.phone,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      online: online,
      lastSeen: lastSeen,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'displayNameLower': displayName.trim().toLowerCase(),
        'email': email,
        'emailLower': email.trim().toLowerCase(),
        'about': about,
        'phone': phone,
        'photoUrl': photoUrl,
        'online': online,
        'lastSeen': writeDateOrNull(lastSeen),
        'createdAt': writeDateOrNull(createdAt),
      };

  factory UserProfile.fromMap(String uid, Map<String, Object?> map) {
    return UserProfile(
      uid: uid,
      displayName: (map['displayName'] as String?)?.trim().isNotEmpty == true
          ? map['displayName']! as String
          : 'Orbit user',
      email: map['email'] as String? ?? '',
      about: map['about'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      online: map['online'] as bool? ?? false,
      lastSeen: readDate(map['lastSeen']),
      createdAt: readDate(map['createdAt']),
    );
  }
}
