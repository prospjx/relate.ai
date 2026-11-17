import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/user_repository.dart';

/// Marks the signed-in user online while the app is in the foreground.
///
/// Firestore has no disconnect hook, so a heartbeat refreshes `lastSeen`
/// and readers treat a stale heartbeat as offline
/// (see [UserProfile.presenceTimeout]).
class PresenceService with WidgetsBindingObserver {
  PresenceService(this._users, this.uid);

  static const heartbeat = Duration(seconds: 60);

  final UserRepository _users;
  final String uid;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _goOnline();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _write(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _goOnline();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
        _write(false);
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _goOnline() {
    _write(true);
    _timer?.cancel();
    _timer = Timer.periodic(heartbeat, (_) => _write(true));
  }

  void _write(bool online) {
    _users.setPresence(uid, online: online).catchError((_) {});
  }
}
