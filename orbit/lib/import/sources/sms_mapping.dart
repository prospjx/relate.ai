import 'dart:io';

import 'package:path/path.dart' as p;

import '../core.dart';
import '../models.dart';
import '../util/address.dart';
import '../util/files.dart';

/// One MMS part. [writeTo] produces the binary content (decoded base64 for
/// XML backups, a content-provider copy on Android); null when the media was
/// not included.
class MmsPart {
  MmsPart(this.attributes, {this.writeTo});

  final Map<String, String> attributes;
  final Future<void> Function(String destinationPath)? writeTo;

  String get contentType => (attributes['ct'] ?? '').toLowerCase();
  int get seq => int.tryParse(attributes['seq'] ?? '') ?? 0;
}

/// Turns Android telephony-style records into [ImportedMessage]s. The
/// attribute names follow the Android SMS/MMS provider columns, which is
/// exactly what SMS Backup & Restore writes, so the XML parser and the
/// on-device importer share this code and therefore produce identical
/// dedupe keys (importing the same message from both never duplicates it).
class SmsRecordMapper {
  SmsRecordMapper(this.options);

  final ReadOptions options;
  final Set<String> _announced = {};
  final Set<String> _learnedOwn = {};

  Set<String> get _own => {...options.ownAddresses, ..._learnedOwn};

  static String? _attr(Map<String, String> a, String key) {
    final v = a[key];
    return (v == null || v == 'null' || v.isEmpty) ? null : v;
  }

  static String? _contactName(Map<String, String> a) {
    final n = _attr(a, 'contact_name');
    return (n == null || n == '(Unknown)') ? null : n;
  }

  Future<void> sms(Map<String, String> a, ImportVisitor visitor, {String? context}) async {
    final address = _attr(a, 'address');
    final date = int.tryParse(a['date'] ?? '');
    final type = int.tryParse(a['type'] ?? '') ?? 1;
    if (type == 3) return; // draft
    if (address == null || date == null) {
      visitor.onIssue(ImportIssue('SMS without address or date skipped', context: context));
      return;
    }
    final isFromMe = type != 1;
    final body = a['body'] ?? '';
    final rcs = a['s_chat'] == '1' || address.contains('@rcs.google.com');
    final thread = ImportedThread(
      key: directThreadKey(address),
      participants: [ImportedParticipant(address: address, displayName: _contactName(a))],
      isGroup: false,
      service: rcs ? MessageService.rcs : MessageService.sms,
    );
    await _announce(thread, visitor);
    await visitor.onMessage(ImportedMessage(
      key: smsKey(address: address, dateMs: date, isFromMe: isFromMe, body: body),
      threadKey: thread.key,
      sentAt: DateTime.fromMillisecondsSinceEpoch(date, isUtc: true),
      isFromMe: isFromMe,
      senderAddress: isFromMe ? null : address,
      service: thread.service,
      text: body,
      isRead: isFromMe || a['read'] == '1',
      subject: _attr(a, 'subject'),
    ));
  }

  static String smsKey({required String address, required int dateMs, required bool isFromMe, required String body}) =>
      'sms:${stableHash([normalizeAddress(address), dateMs, isFromMe ? 1 : 0, body])}';

  Future<void> mms(
    Map<String, String> a,
    List<MmsPart> parts,
    List<Map<String, String>> addrs,
    ImportVisitor visitor, {
    String? context,
  }) async {
    final date = int.tryParse(a['date'] ?? '');
    final box = int.tryParse(a['msg_box'] ?? '') ?? 1;
    if (box == 3) return; // draft
    if (date == null) {
      visitor.onIssue(ImportIssue('MMS without date skipped', context: context));
      return;
    }
    final isFromMe = box != 1;

    String? from;
    final recipients = <String>[];
    for (final ad in addrs) {
      final address = _attr(ad, 'address');
      if (address == null) continue;
      switch (ad['type']) {
        case '137':
          from = address;
        case '151' || '130' || '129':
          recipients.add(address);
      }
    }
    if (isFromMe && from != null && from != 'insert-address-token') _learnedOwn.add(from);

    // Prefer the backup's `address` (all participants joined by "~", never
    // including the owner); fall back to the addr list. Google Messages RCS
    // groups use placeholder "...@rcs.google.com" addresses there, so use
    // the addr list for those.
    final listed = (_attr(a, 'address') ?? '').split('~').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    List<String> participants;
    if (listed.isNotEmpty && !listed.any((s) => s.contains('@rcs.google.com') && !s.contains('@bot.'))) {
      participants = listed;
    } else if (isFromMe) {
      participants = recipients;
    } else {
      // Received: sender + other recipients. A lone "To" is the owner.
      participants = [?from, if (recipients.length > 1) ...recipients];
    }
    participants = participants.where((x) => !isOwnAddress(x, _own)).toSet().toList();
    if (participants.isEmpty) {
      if (from != null && !isOwnAddress(from, _own)) {
        participants = [from];
      } else {
        visitor.onIssue(ImportIssue('MMS with no identifiable participants skipped', context: context));
        return;
      }
    }

    final isGroup = participants.length > 1;
    final trId = _attr(a, 'tr_id');
    final rcs = (trId?.startsWith('proto:') ?? false) ||
        participants.any((x) => x.contains('@rcs.google.com')) ||
        (_attr(a, 'address')?.contains('@rcs.google.com') ?? false);
    final service = rcs ? MessageService.rcs : MessageService.mms;
    final names = isGroup ? null : _contactName(a);
    final thread = ImportedThread(
      key: isGroup ? groupThreadKey(participants) : directThreadKey(participants.single),
      participants: [for (final x in participants) ImportedParticipant(address: x, displayName: names)],
      isGroup: isGroup,
      service: service,
    );
    await _announce(thread, visitor);

    final sorted = [...parts]..sort((x, y) => x.seq.compareTo(y.seq));
    final text = sorted
        .where((x) => x.contentType == 'text/plain' && x.attributes['text'] != null)
        .map((x) => x.attributes['text']!)
        .join('\n')
        .trim();
    final messageId = (_attr(a, 'm_id') ?? trId ?? '').replaceFirst(RegExp(r'^(proto:|smsbr-)'), '');
    final key = 'mms:${stableHash([thread.key, date, isFromMe ? 1 : 0, text, messageId])}';

    final attachments = <ImportedAttachment>[];
    var index = 0;
    for (final part in sorted) {
      final ct = part.contentType;
      if (ct == 'application/smil' || (ct == 'text/plain' && part.attributes['text'] != null)) continue;
      index++;
      final mime = ct.isEmpty ? 'application/octet-stream' : ct;
      final name = safeFileName(_attr(part.attributes, 'cl') ?? _attr(part.attributes, 'name'), mime, fallback: 'part$index');
      if (part.writeTo == null) {
        attachments.add(ImportedAttachment(fileName: name, mimeType: mime, missingReason: 'Media was not included in the backup'));
        continue;
      }
      String? localPath;
      int? size;
      String? missing;
      if (options.extractAttachments && options.attachmentDirectory != null) {
        final dest = p.join(options.attachmentDirectory!, '${stableHash([key, index])}_$name');
        try {
          final f = File(dest);
          if (!await f.exists()) {
            await f.parent.create(recursive: true);
            await part.writeTo!(dest);
          }
          localPath = dest;
          size = await f.length();
        } catch (e) {
          missing = 'Could not save attachment: $e';
          visitor.onIssue(ImportIssue('Attachment "$name" could not be saved: $e', context: context));
        }
      }
      attachments.add(ImportedAttachment(
        fileName: name,
        mimeType: mime,
        localPath: localPath,
        sizeBytes: size,
        missingReason: missing,
      ));
    }
    if (text.isEmpty && attachments.isEmpty) return;

    await visitor.onMessage(ImportedMessage(
      key: key,
      threadKey: thread.key,
      sentAt: DateTime.fromMillisecondsSinceEpoch(date, isUtc: true),
      isFromMe: isFromMe,
      senderAddress: isFromMe ? null : (from ?? (isGroup ? null : participants.single)),
      service: service,
      text: text,
      attachments: attachments,
      isRead: isFromMe || a['read'] == '1',
      subject: _attr(a, 'sub'),
    ));
  }

  Future<void> _announce(ImportedThread thread, ImportVisitor visitor) async {
    if (_announced.add(thread.key)) await visitor.onThread(thread);
  }
}
