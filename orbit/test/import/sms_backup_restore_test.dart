import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/import/import.dart';
import 'package:path/path.dart' as p;

import 'fixtures/builders.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('orbit_sbr_test_'));
  tearDown(() async => tmp.delete(recursive: true));

  ReadOptions options({Set<String> own = const {'+15550009999'}}) =>
      ReadOptions(attachmentDirectory: p.join(tmp.path, 'att'), ownAddresses: own);

  Future<(InMemoryImportSink, ImportSummary)> importFile(String path, {ReadOptions? opts}) async {
    final sink = InMemoryImportSink();
    final summary = await ImportEngine().run(SmsBackupRestoreSource(path), sink, options: opts ?? options());
    return (sink, summary);
  }

  test('parses SMS, group MMS with image, RCS group and skips drafts', () async {
    final (sink, summary) = await importFile(fixturePath('sms_backup_sample.xml'));
    expect(summary.fatalError, isNull);
    expect(summary.messagesAdded, 6);
    expect(sink.threads.keys, unorderedEquals(['dm:5551230001', 'group:5551230001,5551230002', 'dm:bank']));

    final ana = sink.messagesByThread['dm:5551230001']!;
    expect(ana.map((m) => m.text), ['Hi from Ana 😀 & welcome', 'Reply line 1\nline 2 with a > sign <tag>', '']);
    expect(ana[0].isFromMe, isFalse);
    expect(ana[0].senderAddress, '(555) 123-0001');
    expect(ana[0].sentAt, DateTime.utc(2023, 1, 1, 10));
    expect(ana[0].service, MessageService.sms);
    expect(ana[1].isFromMe, isTrue);
    expect(sink.threads['dm:5551230001']!.participants.single.displayName, 'Ana Example');

    // Sent MMS whose media wasn't included in the backup.
    expect(ana[2].service, MessageService.mms);
    expect(ana[2].attachments.single.mimeType, 'image/jpeg');
    expect(ana[2].attachments.single.isAvailable, isFalse);

    final groupThread = sink.threads['group:5551230001,5551230002']!;
    expect(groupThread.isGroup, isTrue);
    expect(groupThread.participants.map((x) => x.address), unorderedEquals(['+15551230001', '+15551230002']));
    final group = sink.messagesByThread[groupThread.key]!;
    expect(group, hasLength(2));
    expect(group[0].text, 'Group photo from Ben');
    expect(group[0].senderAddress, '+15551230002');
    final image = group[0].attachments.single;
    expect(image.mimeType, 'image/png');
    expect(image.fileName, 'image000000.png');
    expect(await File(image.localPath!).readAsBytes(), hasLength(greaterThan(60)));
    expect((await File(image.localPath!).readAsBytes()).sublist(1, 4), 'PNG'.codeUnits);

    expect(group[1].text, 'RCS group message');
    expect(group[1].service, MessageService.rcs);
    expect(group[1].senderAddress, '+15551230001');
    expect(group[1].isRead, isFalse);

    expect(summary.attachments, 1);
    expect(summary.missingAttachments, 1);
  });

  test('without the owner number the RCS group (which lists the owner) stays separate', () async {
    final (sink, _) = await importFile(fixturePath('sms_backup_sample.xml'), opts: options(own: {}));
    expect(sink.threads.keys.where((k) => k.startsWith('group:')), hasLength(2));
  });

  test('re-importing the same file adds nothing (stable keys)', () async {
    final sink = InMemoryImportSink();
    final engine = ImportEngine();
    final first = await engine.run(SmsBackupRestoreSource(fixturePath('sms_backup_sample.xml')), sink, options: options());
    final keys = {for (final l in sink.messagesByThread.values) ...l.map((m) => m.key)};
    final second = await engine.run(SmsBackupRestoreSource(fixturePath('sms_backup_sample.xml')), sink, options: options());
    expect(first.messagesAdded, 6);
    expect(second.messagesAdded, 0);
    expect(second.duplicatesSkipped, 6);
    expect({for (final l in sink.messagesByThread.values) ...l.map((m) => m.key)}, keys);
    expect(sink.messageCount, 6);
  });

  test('reads compressed .xml.zip backups', () async {
    final zip = p.join(tmp.path, 'sms-20240301.xml.zip');
    await writeZip(zip, 'sms-20240301.xml', await File(fixturePath('sms_backup_sample.xml')).readAsBytes());
    final (sink, summary) = await importFile(zip);
    expect(summary.fatalError, isNull);
    expect(sink.messageCount, 6);
  });

  test('preview counts without writing attachments', () async {
    final preview = await ImportEngine().preview(SmsBackupRestoreSource(fixturePath('sms_backup_sample.xml')), options: options());
    expect(preview.threads, 3);
    expect(preview.groupThreads, 1);
    expect(preview.messages, 6);
    expect(preview.attachments, 2);
    expect(preview.missingAttachments, 1);
    expect(preview.earliest, DateTime.utc(2023, 1, 1, 10));
    expect(preview.latest, DateTime.utc(2023, 1, 2, 13));
    expect(preview.byService[MessageService.rcs], 1);
    expect(Directory(p.join(tmp.path, 'att')).existsSync(), isFalse);
  });

  test('rejects call-log backups and other XML with a clear error', () async {
    final calls = File(p.join(tmp.path, 'calls.xml'))..writeAsStringSync('<?xml version="1.0"?><calls count="0"></calls>');
    final (_, s1) = await importFile(calls.path);
    expect(s1.fatalError, contains('call-log'));

    final other = File(p.join(tmp.path, 'other.xml'))..writeAsStringSync('<rss><channel/></rss>');
    final (_, s2) = await importFile(other.path);
    expect(s2.fatalError, contains('SMS Backup & Restore'));
  });

  test('truncated file reports damage but keeps messages read so far', () async {
    final full = await File(fixturePath('sms_backup_sample.xml')).readAsString();
    final cut = File(p.join(tmp.path, 'cut.xml'))..writeAsStringSync(full.substring(0, full.indexOf('<mms ') + 20));
    final (sink, summary) = await importFile(cut.path);
    expect(summary.fatalError, contains('damaged'));
    expect(sink.messageCount, 2);
  });
}
