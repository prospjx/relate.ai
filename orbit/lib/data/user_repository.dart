import 'package:cloud_firestore/cloud_firestore.dart';

import '../import/util/address.dart';
import '../models/models.dart';

/// Reads and writes public profiles at `users/{uid}`, including presence.
class UserRepository {
  UserRepository(this._db);

  static const collection = 'users';

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(collection);

  Stream<UserProfile?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map(
          (snap) => snap.exists ? UserProfile.fromMap(uid, snap.data()!) : null,
        );
  }

  Future<UserProfile?> getUser(String uid) async {
    final snap = await _users.doc(uid).get();
    return snap.exists ? UserProfile.fromMap(uid, snap.data()!) : null;
  }

  /// Creates the profile document if it does not exist yet and returns it.
  Future<UserProfile> ensureProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    final snap = await _users.doc(uid).get();
    if (snap.exists) {
      final data = snap.data()!;
      final existing = UserProfile.fromMap(uid, data);
      final normalized = normalizeAddress(existing.phone);
      if (normalized.isNotEmpty && data['phoneNormalized'] != normalized) {
        await _users.doc(uid).update({'phoneNormalized': normalized});
      }
      return existing;
    }
    final name = (displayName ?? '').trim().isNotEmpty
        ? displayName!.trim()
        : email.split('@').first;
    final profile = UserProfile(uid: uid, displayName: name, email: email);
    await _users.doc(uid).set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    });
    return profile;
  }

  Future<void> updateProfile(
    String uid, {
    String? displayName,
    String? about,
    String? phone,
    String? photoUrl,
    bool clearPhoto = false,
  }) async {
    final changes = <String, Object?>{};
    if (displayName != null) {
      final name = displayName.trim();
      if (name.isEmpty) throw ArgumentError('Display name is required');
      changes['displayName'] = name;
      changes['displayNameLower'] = name.toLowerCase();
    }
    if (about != null) changes['about'] = about.trim();
    if (phone != null) {
      changes['phone'] = phone.trim();
      changes['phoneNormalized'] = normalizeAddress(phone);
    }
    if (photoUrl != null) changes['photoUrl'] = photoUrl;
    if (clearPhoto) changes['photoUrl'] = null;
    if (changes.isEmpty) return;
    await _users.doc(uid).update(changes);
  }

  /// Finds users by exact email, or by display name prefix.
  Future<List<UserProfile>> search(
    String query, {
    String? excludeUid,
    int limit = 20,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final QuerySnapshot<Map<String, dynamic>> snap;
    if (q.contains('@')) {
      snap = await _users.where('emailLower', isEqualTo: q).limit(limit).get();
    } else {
      snap = await _users
          .orderBy('displayNameLower')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(limit)
          .get();
    }
    return snap.docs
        .where((d) => d.id != excludeUid)
        .map((d) => UserProfile.fromMap(d.id, d.data()))
        .toList();
  }

  /// Orbit users whose profile phone number matches one of [numbers], keyed
  /// by normalized number.
  Future<Map<String, UserProfile>> findByPhones(
    Iterable<String> numbers, {
    String? excludeUid,
  }) async {
    final keys = numbers.map(normalizeAddress).where((n) => n.length >= 7).toSet().toList();
    final found = <String, UserProfile>{};
    for (var i = 0; i < keys.length; i += 30) {
      final snap = await _users
          .where('phoneNormalized', whereIn: keys.skip(i).take(30).toList())
          .get();
      for (final d in snap.docs) {
        if (d.id == excludeUid) continue;
        final key = d.data()['phoneNormalized'] as String?;
        if (key != null) found[key] = UserProfile.fromMap(d.id, d.data());
      }
    }
    return found;
  }

  Future<void> setPresence(String uid, {required bool online}) {
    return _users.doc(uid).update({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }
}
