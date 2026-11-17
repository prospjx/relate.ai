import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/import/import.dart';
import 'package:orbit/import/util/sqlite.dart';
import 'package:path/path.dart' as p;

import 'fixtures/builders.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('orbit_imsg_test_'));
  tearDown(() async => tmp.delete(recursive: true));

  group('Mac chat.db', () {
    late InMemoryImportSink sink;
    late ImportSummary summary;
    late String attachmentDir;

    setUp(() async {
      final dbPath = await buildMacMessagesFolder(Directory(p.join(tmp.path, 'Messages'))..createSync());
      attachmentDir = p.join(tmp.path, 'out');
      sink = InMemoryImportSink();
      final source = IMessageDbSource(
        dbPath: dbPath,
        locator: MacAttachmentLocator(p.join(tmp.path, 'Messages', 'Attachments')),
      );
      summary = await ImportEngine().run(source, sink, options: ReadOptions(attachmentDirectory: attachmentDir));
      await source.dispose();
    });

    test('maps chats to threads (1:1, group, SMS + orphan merged by number)', () {
      expect(summary.fatalError, isNull);
      expect(sink.threads.keys, unorderedEquals(['dm:5551230001', 'imsg-group:chat900000000000000001', 'dm:5551230003']));
      final groupThread = sink.threads['imsg-group:chat900000000000000001']!;
      expect(groupThread.isGroup, isTrue);
      expect(groupThread.title, 'Trip Planning');
      expect(groupThread.participants.map((x) => x.address), unorderedEquals([anaPhone, alexEmail]));
      expect(sink.threads['dm:5551230001']!.isGroup, isFalse);
      expect(sink.messagesByThread['dm:5551230003']!.map((m) => m.text), ['Your code is 1234', 'Orphan message']);
    });

    test('decodes text, attributedBody and both date formats', () {
      final ana = sink.messagesByThread['dm:5551230001']!;
      final normal = ana.where((m) => m.kind == ImportedMessageKind.normal).toList();
      expect(normal.map((m) => m.text), ['Hello from Ana', 'Reply stored only in attributedBody ✅']);
      expect(normal[0].sentAt, t0);
      expect(normal[0].senderAddress, anaPhone);
      expect(normal[0].service, MessageService.iMessage);
      expect(normal[0].isRead, isTrue);
      expect(normal[0].readAt, t0.add(const Duration(minutes: 1)));
      expect(normal[0].key, 'imsg:GUID-M1');
      // Stored in legacy seconds.
      expect(normal[1].sentAt, t0.add(const Duration(minutes: 5)));
      expect(normal[1].isFromMe, isTrue);
      expect(normal[1].senderAddress, isNull);
    });

    test('maps tapbacks to reactions on the target message', () {
      final reaction = sink.messagesByThread['dm:5551230001']!.singleWhere((m) => m.kind == ImportedMessageKind.reaction);
      expect(reaction.reaction, '👍');
      expect(reaction.reactionTargetKey, 'imsg:GUID-M1');
      expect(reaction.reactionRemoved, isFalse);
      expect(reaction.isFromMe, isTrue);
    });

    test('copies attachments and records group events', () async {
      final group = sink.messagesByThread['imsg-group:chat900000000000000001']!;
      expect(group[0].text, 'Group hi');
      expect(group[0].senderAddress, alexEmail);
      final photo = group[1].attachments.single;
      expect(group[1].text, isEmpty);
      expect(photo.mimeType, 'image/png');
      expect(photo.fileName, 'photo.png');
      expect(p.isWithin(attachmentDir, photo.localPath!), isTrue);
      expect(File(photo.localPath!).existsSync(), isTrue);
      expect(group[2].kind, ImportedMessageKind.system);
      expect(group[2].text, contains('Trip Planning'));
      expect(summary.attachments, 1);
    });

    test('skips rows without content and reports it', () {
      expect(summary.messagesAdded, 9 - 1);
      expect(summary.issues.map((i) => i.message).join(), contains('1 items had no text'));
    });
  });

  test('re-import is deduplicated by message guid', () async {
    final dbPath = await buildMacMessagesFolder(Directory(p.join(tmp.path, 'Messages'))..createSync());
    final sink = InMemoryImportSink();
    final engine = ImportEngine(batchSize: 2);
    final first = await engine.run(IMessageDbSource(dbPath: dbPath), sink);
    final second = await engine.run(IMessageDbSource(dbPath: dbPath), sink);
    expect(first.messagesAdded, 8);
    expect(second.messagesAdded, 0);
    expect(second.duplicatesSkipped, 8);
  });

  test('without an attachment folder, attachments are reported missing', () async {
    final dbPath = p.join(tmp.path, 'chat.db');
    buildChatDb(dbPath, attachmentPathPrefix: '~/Library/Messages/Attachments');
    final preview = await ImportEngine().preview(IMessageDbSource(dbPath: dbPath));
    expect(preview.threads, 3);
    expect(preview.groupThreads, 1);
    expect(preview.messages, 7);
    expect(preview.reactions, 1);
    expect(preview.attachments, 1);
    expect(preview.missingAttachments, 1);
  });

  test('works with older schemas missing optional columns', () async {
    final dbPath = p.join(tmp.path, 'old.db');
    final db = SqliteDb.open(dbPath, create: true);
    db.execute('''
      CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
      CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, guid TEXT, chat_identifier TEXT);
      CREATE TABLE message (ROWID INTEGER PRIMARY KEY, guid TEXT, text TEXT, handle_id INTEGER, date INTEGER, is_from_me INTEGER);
      CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
      INSERT INTO handle VALUES (1, '+15551230001');
      INSERT INTO chat VALUES (1, 'SMS;-;+15551230001', '+15551230001');
      INSERT INTO message VALUES (1, 'OLD-1', 'old school', 1, 300000000, 0);
      INSERT INTO chat_message_join VALUES (1, 1);
    ''');
    db.close();
    final sink = InMemoryImportSink();
    final summary = await ImportEngine().run(IMessageDbSource(dbPath: dbPath), sink);
    expect(summary.fatalError, isNull);
    final m = sink.messagesByThread['dm:5551230001']!.single;
    expect(m.text, 'old school');
    expect(m.sentAt, DateTime.utc(2010, 7, 5, 5, 20));
  });

  test('clear errors for missing files and non-Messages databases', () async {
    final missing = await ImportEngine().run(IMessageDbSource(dbPath: p.join(tmp.path, 'nope.db')), InMemoryImportSink());
    expect(missing.fatalError, contains('not found'));

    final otherPath = p.join(tmp.path, 'other.db');
    SqliteDb.open(otherPath, create: true)
      ..execute('CREATE TABLE notes (id INTEGER)')
      ..close();
    final other = await ImportEngine().run(IMessageDbSource(dbPath: otherPath), InMemoryImportSink());
    expect(other.fatalError, contains('not a Messages database'));

    final junk = File(p.join(tmp.path, 'junk.db'))..writeAsBytesSync(List.generate(8192, (i) => (i * 31) & 0xFF));
    final junkSummary = await ImportEngine().run(IMessageDbSource(dbPath: junk.path), InMemoryImportSink());
    expect(junkSummary.fatalError, isNotNull);
  });

  test('never modifies the original database', () async {
    final dbPath = p.join(tmp.path, 'chat.db');
    buildChatDb(dbPath, attachmentPathPrefix: '~/Library/Messages/Attachments');
    final before = await File(dbPath).readAsBytes();
    final modified = await File(dbPath).lastModified();
    await ImportEngine().run(IMessageDbSource(dbPath: dbPath), InMemoryImportSink());
    expect(await File(dbPath).readAsBytes(), before);
    expect(await File(dbPath).lastModified(), modified);
  });
}
