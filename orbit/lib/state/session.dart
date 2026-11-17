import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/services.dart';
import '../models/models.dart';
import '../services/presence_service.dart';

/// The signed-in user's profile, kept live, plus presence for this device.
class Session extends ChangeNotifier {
  Session({required this.services, required this.uid, required this.email})
      : _presence = PresenceService(services.users, uid);

  final OrbitServices services;
  final String uid;
  final String email;
  final PresenceService _presence;
  StreamSubscription<UserProfile?>? _sub;

  UserProfile? me;

  String get displayName => me?.displayName ?? email.split('@').first;

  Future<void> start({String? displayName}) async {
    try {
      me = await services.users.ensureProfile(
        uid: uid,
        email: email,
        displayName: displayName,
      );
      notifyListeners();
    } catch (_) {
      // Offline on first launch; the live listener below fills in later.
    }
    _sub = services.users.watchUser(uid).listen((profile) {
      if (profile == null) return;
      me = profile;
      notifyListeners();
    }, onError: (_) {});
    _presence.start();
  }

  @override
  void dispose() {
    _presence.stop();
    _sub?.cancel();
    super.dispose();
  }
}
