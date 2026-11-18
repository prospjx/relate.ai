import 'package:flutter/services.dart';

import '../core.dart';
import '../models.dart';
import 'sms_mapping.dart';

class AndroidSmsStatus {
  const AndroidSmsStatus({
    required this.hasPermission,
    this.isDefaultSmsApp = false,
    this.smsCount = 0,
    this.mmsCount = 0,
  });

  final bool hasPermission;
  final bool isDefaultSmsApp;
  final int smsCount;
  final int mmsCount;
}

/// Native side of the on-device Android importer (Telephony SMS/MMS
/// content providers). Records use the provider's column names with every
/// value as a string; MMS `date` must already be converted to milliseconds.
abstract class AndroidSmsBridge {
  Future<AndroidSmsStatus> status();

  /// Shows the READ_SMS runtime permission prompt. Returns true if granted.
  Future<bool> requestPermission();

  /// SMS rows with `_id > afterId`, ascending `_id`, at most [limit].
  Future<List<Map<String, String>>> querySms({required int afterId, required int limit});

  /// MMS rows with `_id > afterId`. Each map has the `pdu` columns plus
  /// `parts` (list of part column maps) and `addrs` (list of addr maps).
  Future<List<Map<String, Object?>>> queryMms({required int afterId, required int limit});

  /// Copies `content://mms/part/{partId}` to [destinationPath].
  Future<void> copyPart({required String partId, required String destinationPath});
}

/// MethodChannel contract (see docs/IMPORT.md and
/// android/app/src/main/kotlin/com/orbit/orbit/OrbitSmsImportPlugin.kt for
/// the Kotlin side):
///
/// channel `orbit/sms_import`
/// * `status` -> {hasPermission: bool, isDefaultSmsApp: bool, smsCount: int, mmsCount: int}
/// * `requestPermission` -> bool
/// * `querySms` {afterId: int, limit: int} -> `List<Map<String, String?>>`
/// * `queryMms` {afterId: int, limit: int} -> `List<Map>` with `parts`, `addrs`
/// * `copyPart` {partId: String, destinationPath: String} -> int (bytes)
/// * `countSince` {smsAfterId: int, mmsAfterId: int} -> {sms: int, mms: int}
/// * `contactsStatus` -> bool, `requestContactsPermission` -> bool
/// * `queryContacts` -> `List<Map>` {contactId, name, number, normalizedNumber, photoUri}
/// * `readPhoto` {uri: String} -> bytes
/// * `openSmsInvite` {number: String, body: String}
class MethodChannelAndroidSmsBridge implements AndroidSmsBridge {
  MethodChannelAndroidSmsBridge([MethodChannel? channel]) : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'orbit/sms_import';
  static const changesChannelName = 'orbit/sms_changes';
  final MethodChannel _channel;

  /// Emits whenever the phone's SMS/MMS store changes while the app runs.
  Stream<void> changes() =>
      const EventChannel(changesChannelName).receiveBroadcastStream();

  @override
  Future<AndroidSmsStatus> status() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('status') ?? const {};
      return AndroidSmsStatus(
        hasPermission: m['hasPermission'] == true,
        isDefaultSmsApp: m['isDefaultSmsApp'] == true,
        smsCount: (m['smsCount'] as num?)?.toInt() ?? 0,
        mmsCount: (m['mmsCount'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      throw const ImportException('This build of Orbit does not include the Android SMS reader.',
          hint: 'Use an SMS Backup & Restore file instead.');
    }
  }

  @override
  Future<bool> requestPermission() async => await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<List<Map<String, String>>> querySms({required int afterId, required int limit}) async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('querySms', {'afterId': afterId, 'limit': limit});
    return [for (final r in rows ?? const <Map<Object?, Object?>>[]) stringMap(r)];
  }

  @override
  Future<List<Map<String, Object?>>> queryMms({required int afterId, required int limit}) async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('queryMms', {'afterId': afterId, 'limit': limit});
    return [for (final r in rows ?? const <Map<Object?, Object?>>[]) r.map((k, v) => MapEntry(k.toString(), v))];
  }

  @override
  Future<void> copyPart({required String partId, required String destinationPath}) =>
      _channel.invokeMethod<int>('copyPart', {'partId': partId, 'destinationPath': destinationPath});

  /// SMS plus MMS rows newer than the given provider ids.
  Future<int> countSince({required int smsAfterId, required int mmsAfterId}) async {
    final m = await _channel.invokeMapMethod<String, Object?>(
            'countSince', {'smsAfterId': smsAfterId, 'mmsAfterId': mmsAfterId}) ??
        const {};
    return ((m['sms'] as num?)?.toInt() ?? 0) + ((m['mms'] as num?)?.toInt() ?? 0);
  }

  Future<bool> hasContactsPermission() async =>
      await _channel.invokeMethod<bool>('contactsStatus') ?? false;

  Future<bool> requestContactsPermission() async =>
      await _channel.invokeMethod<bool>('requestContactsPermission') ?? false;

  Future<List<Map<String, String>>> queryContacts() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('queryContacts');
    return [for (final r in rows ?? const <Map<Object?, Object?>>[]) stringMap(r)];
  }

  Future<Uint8List?> readPhoto(String uri) =>
      _channel.invokeMethod<Uint8List>('readPhoto', {'uri': uri});

  Future<void> openSmsInvite({required String number, required String body}) =>
      _channel.invokeMethod<void>('openSmsInvite', {'number': number, 'body': body});
}

Map<String, String> stringMap(Map<Object?, Object?> raw) => {
      for (final e in raw.entries)
        if (e.value != null && e.value is! List && e.value is! Map) e.key.toString(): e.value.toString(),
    };

/// Imports straight from the phone's SMS/MMS store. Only possible when Orbit
/// is installed outside Google Play (sideloaded) or is the default SMS app:
/// Google Play restricts READ_SMS to default SMS handlers.
class AndroidDeviceSmsSource extends ImportSource {
  AndroidDeviceSmsSource({
    AndroidSmsBridge? bridge,
    this.pageSize = 500,
    this.smsAfterId = 0,
    this.mmsAfterId = 0,
    this.promptForPermission = true,
    this.maxPages,
  })  : bridge = bridge ?? MethodChannelAndroidSmsBridge(),
        lastSmsId = smsAfterId,
        lastMmsId = mmsAfterId;

  final AndroidSmsBridge bridge;
  final int pageSize;

  /// Only rows with a larger provider `_id` are read, so a sync can pick up
  /// where the previous one stopped.
  final int smsAfterId;
  final int mmsAfterId;

  /// When false, a missing permission fails instead of showing the prompt
  /// (for syncs the user didn't start).
  final bool promptForPermission;

  /// Stop after reading this many pages (SMS and MMS pages together) so a
  /// caller can save its progress between runs. Null reads everything.
  final int? maxPages;

  /// Highest `_id` read so far; pass these back as the next `...AfterId`.
  int lastSmsId;
  int lastMmsId;

  /// Rows read by the last [read].
  int rowsRead = 0;

  /// True when [read] stopped because of [maxPages] (more rows may remain).
  bool hasMore = false;

  @override
  String get displayName => 'Messages on this phone';

  @override
  Future<void> read(
    ImportVisitor visitor, {
    required ReadOptions options,
    required CancellationToken token,
    ProgressCallback? onProgress,
  }) async {
    var status = await bridge.status();
    if (!status.hasPermission) {
      if (!promptForPermission || !await bridge.requestPermission()) {
        throw const ImportException('Orbit needs permission to read your text messages.',
            hint: 'Allow "SMS" permission for Orbit in Android Settings > Apps > Orbit > Permissions.');
      }
      status = await bridge.status();
    }
    final total = status.smsCount + status.mmsCount;
    final mapper = SmsRecordMapper(options);
    var processed = 0;
    rowsRead = 0;
    hasMore = false;
    // Only pages that returned rows count, so an exhausted SMS table never
    // uses up the budget the MMS table needs.
    var pagesLeft = maxPages;
    bool canRead() {
      if (pagesLeft != 0) return true;
      hasMore = true;
      return false;
    }

    void pageRead() {
      if (pagesLeft != null) pagesLeft = pagesLeft! - 1;
    }

    for (var afterId = smsAfterId;;) {
      token.throwIfCancelled();
      if (!canRead()) return;
      final rows = await bridge.querySms(afterId: afterId, limit: pageSize);
      if (rows.isEmpty) break;
      pageRead();
      for (final r in rows) {
        token.throwIfCancelled();
        processed++;
        rowsRead++;
        await mapper.sms(r, visitor, context: 'sms _id ${r['_id']}');
        afterId = int.tryParse(r['_id'] ?? '') ?? afterId;
        lastSmsId = afterId;
      }
      onProgress?.call(ImportProgress(phase: 'Reading SMS', processed: processed, total: total));
      if (rows.length < pageSize) break;
    }

    for (var afterId = mmsAfterId;;) {
      token.throwIfCancelled();
      if (!canRead()) return;
      final rows = await bridge.queryMms(afterId: afterId, limit: pageSize);
      if (rows.isEmpty) break;
      pageRead();
      for (final r in rows) {
        token.throwIfCancelled();
        processed++;
        rowsRead++;
        final attrs = stringMap(r);
        final parts = [
          for (final raw in (r['parts'] as List? ?? const []).cast<Map<Object?, Object?>>())
            _part(stringMap(raw)),
        ];
        final addrs = [
          for (final raw in (r['addrs'] as List? ?? const []).cast<Map<Object?, Object?>>()) stringMap(raw),
        ];
        await mapper.mms(attrs, parts, addrs, visitor, context: 'mms _id ${attrs['_id']}');
        afterId = int.tryParse(attrs['_id'] ?? '') ?? afterId;
        lastMmsId = afterId;
      }
      onProgress?.call(ImportProgress(phase: 'Reading MMS', processed: processed, total: total));
      if (rows.length < pageSize) break;
    }
  }

  MmsPart _part(Map<String, String> attrs) {
    final id = attrs['_id'];
    final isText = (attrs['ct'] ?? '').toLowerCase() == 'text/plain' && attrs['text'] != null;
    final isSmil = (attrs['ct'] ?? '').toLowerCase() == 'application/smil';
    return MmsPart(
      attrs,
      writeTo: id == null || isText || isSmil
          ? null
          : (dest) => bridge.copyPart(partId: id, destinationPath: dest),
    );
  }
}
