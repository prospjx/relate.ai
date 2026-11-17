import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core.dart';
import '../models.dart';
import '../util/xml_pull.dart';
import '../util/zip_entry.dart';
import 'sms_mapping.dart';

/// Reads an "SMS Backup & Restore" (SyncTech) backup: `sms-*.xml` or the
/// compressed `sms-*.xml.zip`. Streams the file, so very large backups are
/// fine; attachments (base64 `data` on `<part>`) are decoded straight to
/// files in [ReadOptions.attachmentDirectory].
///
/// Format reference: https://www.synctech.com.au/sms-backup-restore/fields-in-xml-backup-files/
class SmsBackupRestoreSource extends ImportSource {
  SmsBackupRestoreSource(this.filePath);

  final String filePath;

  @override
  String get displayName => 'SMS Backup & Restore';

  @override
  Future<void> read(
    ImportVisitor visitor, {
    required ReadOptions options,
    required CancellationToken token,
    ProgressCallback? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) throw ImportException('File not found: $filePath');

    final Stream<List<int>> bytes;
    if (p.extension(filePath).toLowerCase() == '.zip') {
      bytes = await openZipEntry(file, match: (name) => name.toLowerCase().endsWith('.xml'));
    } else {
      bytes = file.openRead();
    }

    final mapper = SmsRecordMapper(options);
    var total = 0;
    var processed = 0;
    var sawRoot = false;
    Map<String, String>? mms;
    final parts = <MmsPart>[];
    final addrs = <Map<String, String>>[];

    void progress() => onProgress?.call(ImportProgress(
          phase: 'Reading backup',
          processed: processed,
          total: total == 0 ? null : total,
        ));

    Future<void> finishMms() async {
      final attrs = mms!;
      mms = null;
      processed++;
      await mapper.mms(attrs, List.of(parts), List.of(addrs), visitor, context: 'MMS #$processed');
      parts.clear();
      addrs.clear();
    }

    try {
      final tokens = xmlTokens(bytes.transform(const Utf8Decoder(allowMalformed: true)));
      await for (final t in tokens) {
        token.throwIfCancelled();
        switch (t) {
          case XmlStartTag(name: 'smses', :final attributes):
            sawRoot = true;
            total = int.tryParse(attributes['count'] ?? '') ?? 0;
          case XmlStartTag(name: 'calls'):
            throw const ImportException('This is a call-log backup, not a messages backup.',
                hint: 'Choose the file that starts with "sms-".');
          case XmlStartTag(name: 'sms', :final attributes):
            processed++;
            await mapper.sms(attributes, visitor, context: 'SMS #$processed');
            if (processed % 200 == 0) progress();
          case XmlStartTag(name: 'mms', :final attributes, :final selfClosing):
            mms = attributes;
            if (selfClosing) await finishMms();
          case XmlStartTag(name: 'part', :final attributes) when mms != null:
            final data = attributes.remove('data');
            parts.add(MmsPart(
              attributes,
              writeTo: data == null || data.isEmpty ? null : (dest) => _writeBase64(data, dest),
            ));
          case XmlStartTag(name: 'addr', :final attributes) when mms != null:
            addrs.add(attributes);
          case XmlEndTag(name: 'mms') when mms != null:
            await finishMms();
            if (processed % 50 == 0) progress();
          default:
            if (!sawRoot && t is XmlStartTag) {
              throw ImportException('This does not look like an SMS Backup & Restore file (found <${t.name}>).');
            }
        }
      }
    } on XmlFormatException catch (e) {
      throw ImportException('The backup file is damaged: ${e.message}',
          hint: 'Make a new backup and copy it again; the file may be incomplete.');
    }
    if (!sawRoot) {
      throw const ImportException('This does not look like an SMS Backup & Restore file.');
    }
    progress();
  }

  static Future<void> _writeBase64(String data, String dest) async {
    final clean = data.contains(RegExp(r'\s')) ? data.replaceAll(RegExp(r'\s'), '') : data;
    await File(dest).writeAsBytes(base64.decode(clean), flush: true);
  }
}
