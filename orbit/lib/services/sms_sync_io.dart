import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../data/orbit_import_sink.dart';
import '../data/services.dart';
import '../import/core.dart';
import '../import/engine.dart';
import '../import/sources/android_device_source.dart';
import '../import/ui/import_screen.dart' show defaultImportAttachmentDirectory;
import '../import/util/address.dart';
import '../import/util/contacts.dart';
import '../models/phone_contact.dart';
import 'sms_sync.dart';

SmsSync createSmsSync({
  required OrbitServices services,
  required String uid,
  required String Function() displayName,
}) =>
    Platform.isAndroid
        ? AndroidSmsSync(services: services, uid: uid, displayName: displayName)
        : SmsSync();

/// Syncs when turned on, when the app opens or returns to the foreground,
/// and a few seconds after the phone's SMS store changes. Each run reads
/// one page of rows newer than the last synced provider ids, saves them,
/// then records its position, so closing the app mid-sync loses at most one
/// page. The sink skips anything already imported, so overlapping or
/// repeated runs are harmless.
class AndroidSmsSync extends SmsSync with WidgetsBindingObserver {
  AndroidSmsSync({
    required this.services,
    required this.uid,
    required this.displayName,
    MethodChannelAndroidSmsBridge? bridge,
  }) : _bridge = bridge ?? MethodChannelAndroidSmsBridge() {
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  /// Bumped when earlier syncs may have stored bad data; older state files
  /// restart from the first text.
  static const stateVersion = 2;
  static const _debounce = Duration(seconds: 3);
  static const _uploadTimeout = Duration(seconds: 30);

  final OrbitServices services;
  final String uid;
  final String Function() displayName;
  final MethodChannelAndroidSmsBridge _bridge;

  bool _enabled = false;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;
  int _smsId = 0;
  int _mmsId = 0;
  DateTime? _lastSyncedAt;
  int _lastAdded = 0;
  String? _error;
  int _progressDone = 0;
  int _progressTotal = 0;
  StreamSubscription<void>? _changes;
  Timer? _pending;

  bool _contactsAllowed = false;
  List<PhoneContact> _contacts = const [];
  ContactBook? _book;
  String? _contactsSignature;
  Future<void>? _contactsLoading;
  final Map<String, Future<Uint8List?>> _photos = {};

  @override
  bool get supported => true;
  @override
  bool get enabled => _enabled;
  @override
  bool get syncing => _running;
  @override
  DateTime? get lastSyncedAt => _lastSyncedAt;
  @override
  int get lastAdded => _lastAdded;
  @override
  String? get error => _error;
  @override
  int get progressDone => _progressDone;
  @override
  int get progressTotal => _progressTotal;
  @override
  bool get contactsAllowed => _contactsAllowed;
  @override
  List<PhoneContact> get contacts => _contacts;

  /// The saved (smsId, mmsId) position, or null when the state was written
  /// by an older version and the sync must start over.
  static (int, int)? cursorsFromState(Map<String, dynamic> state) {
    if ((state['version'] as num?)?.toInt() != stateVersion) return null;
    return (
      (state['smsId'] as num?)?.toInt() ?? 0,
      (state['mmsId'] as num?)?.toInt() ?? 0,
    );
  }

  File get _stateFile => File(p.join(
        p.dirname(defaultImportAttachmentDirectory()),
        'sms_sync_$uid.json',
      ));

  Future<void> _load() async {
    var reset = false;
    try {
      final file = _stateFile;
      if (await file.exists()) {
        final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _enabled = m['enabled'] == true;
        final cursors = cursorsFromState(m);
        if (cursors != null) {
          _smsId = cursors.$1;
          _mmsId = cursors.$2;
          _contactsSignature = m['contactsSignature'] as String?;
          final at = m['lastSyncedAt'] as String?;
          _lastSyncedAt = at == null ? null : DateTime.tryParse(at);
        } else {
          reset = true;
        }
      }
    } catch (_) {
      // A corrupt state file just means the next sync starts from the top;
      // already imported messages are skipped.
    }
    if (_disposed) return;
    if (reset) await _save();
    notifyListeners();
    await _loadContacts();
    if (_enabled && !_disposed) _start();
  }

  Future<void> _save() async {
    final file = _stateFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'version': stateVersion,
      'enabled': _enabled,
      'smsId': _smsId,
      'mmsId': _mmsId,
      'lastSyncedAt': _lastSyncedAt?.toIso8601String(),
      'contactsSignature': _contactsSignature,
    }));
  }

  void _start() {
    _changes ??= _bridge.changes().listen((_) {
      _pending?.cancel();
      _pending = Timer(_debounce, syncNow);
    }, onError: (_) {});
    syncNow();
  }

  void _stop() {
    _pending?.cancel();
    _changes?.cancel();
    _changes = null;
  }

  @override
  Future<bool> enable() async {
    _error = null;
    try {
      final status = await _bridge.status();
      if (!status.hasPermission && !await _bridge.requestPermission()) {
        _error = 'Orbit needs permission to read your texts. Allow "SMS" '
            'for Orbit in Settings > Apps > Orbit > Permissions.';
        notifyListeners();
        return false;
      }
    } on ImportException catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
    // Names are optional: without them chats show phone numbers.
    await allowContacts();
    _enabled = true;
    await _save();
    notifyListeners();
    _start();
    return true;
  }

  @override
  Future<void> disable() async {
    _enabled = false;
    _stop();
    await _save();
    notifyListeners();
  }

  @override
  Future<bool> allowContacts() async {
    try {
      if (!await _bridge.hasContactsPermission() &&
          !await _bridge.requestContactsPermission()) {
        return false;
      }
    } catch (_) {
      return false;
    }
    await _loadContacts();
    return _contactsAllowed;
  }

  /// Reads the phone's contacts. When they changed since the last time,
  /// relabels chats that were already imported.
  Future<void> _loadContacts() => _contactsLoading ??= () async {
        try {
          _contactsAllowed = await _bridge.hasContactsPermission();
          if (!_contactsAllowed) return;
          final rows = await _bridge.queryContacts();
          _contacts = PhoneContact.fromRows(rows);
          final book = ContactBook.fromPhoneRows(rows);
          _book = book;
          if (!_disposed) notifyListeners();
          final signature = stableHash([
            for (final c in _contacts) '${c.name}\u0001${c.normalizedNumber}',
          ]);
          if (signature != _contactsSignature) {
            await services.chats.refreshImportedNames(
              importerUid: uid,
              source: OrbitImportSink.source,
              lookup: book.lookup,
            );
            _contactsSignature = signature;
            await _save();
          }
        } catch (_) {
          // Contacts only add names; a failure leaves chats labelled by number.
        } finally {
          _contactsLoading = null;
        }
      }();

  @override
  Future<Uint8List?> contactPhoto(PhoneContact contact) {
    final uri = contact.photoUri;
    if (uri == null || uri.isEmpty) return Future.value(null);
    return _photos.putIfAbsent(uri, () async {
      try {
        return await _bridge.readPhoto(uri);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<void> inviteBySms(String number, String body) =>
      _bridge.openSmsInvite(number: number, body: body);

  @override
  Future<void> syncNow() async {
    if (!_enabled || _disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _error = null;
    notifyListeners();
    // Once Storage refuses an upload, the remaining attachments in this run
    // become notes instead of each waiting for their own failure.
    var uploadsDown = false;
    final sink = OrbitImportSink(
      chats: services.chats,
      importerUid: uid,
      importerName: displayName(),
      readFile: (path) => File(path).readAsBytes(),
      upload: ({
        required conversationId,
        required kind,
        required bytes,
        required fileName,
        required mimeType,
      }) async {
        if (uploadsDown) throw StateError('Uploads are unavailable');
        try {
          return await services.media
              .uploadChatFile(
                conversationId: conversationId,
                uploaderUid: uid,
                kind: kind,
                bytes: bytes,
                fileName: fileName,
                mimeType: mimeType,
              )
              .timeout(_uploadTimeout);
        } catch (_) {
          uploadsDown = true;
          rethrow;
        }
      },
    );
    try {
      await _contactsLoading;
      do {
        _again = false;
        var added = 0;
        _progressDone = 0;
        try {
          _progressTotal = await _bridge.countSince(smsAfterId: _smsId, mmsAfterId: _mmsId);
        } catch (_) {
          _progressTotal = 0;
        }
        notifyListeners();
        while (_enabled && !_disposed) {
          final source = AndroidDeviceSmsSource(
            bridge: _bridge,
            smsAfterId: _smsId,
            mmsAfterId: _mmsId,
            promptForPermission: false,
            maxPages: 1,
          );
          final summary = await ImportEngine(contacts: _book).run(
            source,
            sink,
            options: ReadOptions(attachmentDirectory: defaultImportAttachmentDirectory()),
          );
          if (summary.fatalError != null) {
            _error = summary.fatalError;
            return;
          }
          _smsId = source.lastSmsId;
          _mmsId = source.lastMmsId;
          added += summary.messagesAdded;
          _progressDone += source.rowsRead;
          _lastSyncedAt = DateTime.now();
          await _save();
          if (!_disposed) notifyListeners();
          if (!source.hasMore) break;
        }
        _lastAdded = added;
      } while (_again && _enabled && !_disposed);
    } catch (e) {
      _error = 'Could not sync your texts: $e';
    } finally {
      _running = false;
      _progressDone = 0;
      _progressTotal = 0;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _loadContacts();
    syncNow();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }
}
