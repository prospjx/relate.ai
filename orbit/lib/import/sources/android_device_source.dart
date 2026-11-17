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
/// lib/import/android/OrbitSmsImportPlugin.kt for the Kotlin side):
///
/// channel `orbit/sms_import`
/// * `status` -> {hasPermission: bool, isDefaultSmsApp: bool, smsCount: int, mmsCount: int}
/// * `requestPermission` -> bool
/// * `querySms` {afterId: int, limit: int} -> `List<Map<String, String?>>`
/// * `queryMms` {afterId: int, limit: int} -> `List<Map>` with `parts`, `addrs`
/// * `copyPart` {partId: String, destinationPath: String} -> int (bytes)
class MethodChannelAndroidSmsBridge implements AndroidSmsBridge {
  MethodChannelAndroidSmsBridge([MethodChannel? channel]) : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'orbit/sms_import';
  final MethodChannel _channel;

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
}

Map<String, String> stringMap(Map<Object?, Object?> raw) => {
      for (final e in raw.entries)
        if (e.value != null && e.value is! List && e.value is! Map) e.key.toString(): e.value.toString(),
    };

/// Imports straight from the phone's SMS/MMS store. Only possible when Orbit
/// is installed outside Google Play (sideloaded) or is the default SMS app:
/// Google Play restricts READ_SMS to default SMS handlers.
class AndroidDeviceSmsSource extends ImportSource {
  AndroidDeviceSmsSource({AndroidSmsBridge? bridge, this.pageSize = 500})
      : bridge = bridge ?? MethodChannelAndroidSmsBridge();

  final AndroidSmsBridge bridge;
  final int pageSize;

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
      if (!await bridge.requestPermission()) {
        throw const ImportException('Orbit needs permission to read your text messages.',
            hint: 'Allow "SMS" permission for Orbit in Android Settings > Apps > Orbit > Permissions.');
      }
      status = await bridge.status();
    }
    final total = status.smsCount + status.mmsCount;
    final mapper = SmsRecordMapper(options);
    var processed = 0;

    for (var afterId = 0;;) {
      token.throwIfCancelled();
      final rows = await bridge.querySms(afterId: afterId, limit: pageSize);
      if (rows.isEmpty) break;
      for (final r in rows) {
        token.throwIfCancelled();
        processed++;
        await mapper.sms(r, visitor, context: 'sms _id ${r['_id']}');
        afterId = int.tryParse(r['_id'] ?? '') ?? afterId;
      }
      onProgress?.call(ImportProgress(phase: 'Reading SMS', processed: processed, total: total));
      if (rows.length < pageSize) break;
    }

    for (var afterId = 0;;) {
      token.throwIfCancelled();
      final rows = await bridge.queryMms(afterId: afterId, limit: pageSize);
      if (rows.isEmpty) break;
      for (final r in rows) {
        token.throwIfCancelled();
        processed++;
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
