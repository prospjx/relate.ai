import 'package:flutter/foundation.dart';

import '../data/services.dart';
import '../models/phone_contact.dart';
import 'sms_sync_stub.dart' if (dart.library.io) 'sms_sync_io.dart' as impl;

/// Keeps the texts on this phone copied into Orbit and reads the phone's
/// contacts to name them. Only does anything on Android; elsewhere
/// [supported] is false and every call is a no-op.
class SmsSync extends ChangeNotifier {
  SmsSync();

  factory SmsSync.forUser({
    required OrbitServices services,
    required String uid,
    required String Function() displayName,
  }) =>
      impl.createSmsSync(services: services, uid: uid, displayName: displayName);

  bool get supported => false;
  bool get enabled => false;
  bool get syncing => false;
  DateTime? get lastSyncedAt => null;

  /// Messages added by the most recent sync.
  int get lastAdded => 0;
  String? get error => null;

  /// Texts read so far by the running sync, out of [progressTotal].
  int get progressDone => 0;
  int get progressTotal => 0;

  /// Asks for the SMS and contacts permissions, then copies every text on
  /// the phone and keeps syncing new ones. Returns false if SMS permission
  /// was refused (contacts are optional).
  Future<bool> enable() async => false;

  /// Stops syncing. Texts already copied stay in Orbit.
  Future<void> disable() async {}

  Future<void> syncNow() async {}

  /// Whether Orbit may read the phone's contacts.
  bool get contactsAllowed => false;

  /// The phone's contacts, sorted by name. Empty until [contactsAllowed].
  List<PhoneContact> get contacts => const [];

  /// Shows the contacts permission prompt and loads contacts if granted.
  Future<bool> allowContacts() async => false;

  Future<Uint8List?> contactPhoto(PhoneContact contact) async => null;

  /// Opens the phone's SMS app with [body] addressed to [number].
  Future<void> inviteBySms(String number, String body) async {}
}
