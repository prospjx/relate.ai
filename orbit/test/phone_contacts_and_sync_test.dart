import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/chat_repository.dart';
import 'package:orbit/data/user_repository.dart';
import 'package:orbit/import/import.dart';
import 'package:orbit/models/models.dart';
import 'package:orbit/models/phone_contact.dart';
import 'package:orbit/services/sms_sync_io.dart';
import 'package:path/path.dart' as p;

import 'import/engine_and_android_test.dart' show bridgeFromFixture;

void main() {
  group('phone contacts', () {
    final rows = [
      {'contactId': '1', 'name': 'Ben Example', 'number': '(555) 123-0002', 'normalizedNumber': '+15551230002'},
      {'contactId': '1', 'name': 'Ben Example', 'number': '+1 555 123 0002'},
      {'contactId': '2', 'name': 'ann lee', 'number': '+15551230001'},
      {'contactId': '3', 'name': '', 'number': '54038'},
    ];

    test('ContactBook matches any formatting of a number', () {
      final book = ContactBook.fromPhoneRows(rows);
      expect(book.lookup('+15551230002'), 'Ben Example');
      expect(book.lookup('5551230002'), 'Ben Example');
      expect(book.lookup('555-123-0001'), 'ann lee');
      expect(book.lookup('54038'), isNull);
    });

    test('PhoneContact list is sorted, deduped, and never nameless', () {
      final contacts = PhoneContact.fromRows(rows);
      expect(contacts.map((c) => c.name), ['54038', 'ann lee', 'Ben Example']);
      expect(contacts.last.normalizedNumber, '5551230002');
    });
  });

  group('resumable phone sync', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('orbit_sync_test_'));
    tearDown(() async => tmp.delete(recursive: true));

    test('one page per run saves each page and ends with everything imported', () async {
      final bridge = await bridgeFromFixture();
      final sink = InMemoryImportSink();
      final options = ReadOptions(
        attachmentDirectory: p.join(tmp.path, 'att'),
        ownAddresses: const {'+15550009999'},
      );
      var smsId = 0, mmsId = 0, runs = 0;
      final savedAfterRun = <int>[];
      while (true) {
        final source = AndroidDeviceSmsSource(
          bridge: bridge,
          pageSize: 2,
          smsAfterId: smsId,
          mmsAfterId: mmsId,
          maxPages: 1,
        );
        final summary = await ImportEngine().run(source, sink, options: options);
        expect(summary.fatalError, isNull);
        smsId = source.lastSmsId;
        mmsId = source.lastMmsId;
        savedAfterRun.add(sink.messageCount);
        runs++;
        expect(runs, lessThan(20), reason: 'sync must terminate');
        if (!source.hasMore) break;
      }
      expect(sink.messageCount, 6);
      expect(runs, greaterThan(2));
      // Messages are written after every page, not only at the very end.
      expect(savedAfterRun.first, greaterThan(0));
      expect(savedAfterRun.first, lessThan(6));

      final again = AndroidDeviceSmsSource(bridge: bridge, smsAfterId: smsId, mmsAfterId: mmsId, maxPages: 1);
      final idle = await ImportEngine().run(again, sink, options: options);
      expect(idle.messagesAdded + idle.duplicatesSkipped, 0);
      expect(again.hasMore, isFalse);
    });

    test('state from before the fix restarts from the first text', () {
      expect(AndroidSmsSync.cursorsFromState({'enabled': true, 'smsId': 900, 'mmsId': 80}), isNull);
      expect(
        AndroidSmsSync.cursorsFromState({'version': AndroidSmsSync.stateVersion, 'smsId': 900, 'mmsId': 80}),
        (900, 80),
      );
    });

    test('a failing thread does not stop the other threads from saving', () async {
      final sink = _FailingSink('dm:2');
      final summary = await ImportEngine().run(_TwoThreads(), sink);
      expect(summary.fatalError, contains('boom'));
      expect(sink.messagesByThread['dm:1'], hasLength(1));
      expect(sink.messagesByThread['dm:3'], hasLength(1));
    });
  });

  group('refreshImportedNames', () {
    test('renames people and generated group titles only', () async {
      final db = FakeFirebaseFirestore();
      final chats = ChatRepository(db);
      await chats.upsertImportedConversation(
        importerUid: 'me',
        source: 'phone',
        externalKey: 'dm:5551230001',
        participants: const [Participant(address: '+15551230001')],
      );
      await chats.upsertImportedConversation(
        importerUid: 'me',
        source: 'phone',
        externalKey: 'group:a',
        type: ConversationType.group,
        name: '+15551230001, +15551230002',
        participants: const [
          Participant(address: '+15551230001'),
          Participant(address: '+15551230002'),
        ],
      );
      await chats.upsertImportedConversation(
        importerUid: 'me',
        source: 'phone',
        externalKey: 'group:b',
        type: ConversationType.group,
        name: 'Family',
        participants: const [Participant(address: '+15551230001')],
      );
      final book = ContactBook({'5551230001': 'Ann Lee'});

      final changed = await chats.refreshImportedNames(
        importerUid: 'me',
        source: 'phone',
        lookup: book.lookup,
      );
      expect(changed, 3);
      Future<Conversation> get(String key) async => (await chats.getConversation(
            ChatRepository.importedConversationId(importerUid: 'me', source: 'phone', externalKey: key),
          ))!;
      expect((await get('dm:5551230001')).externalParticipants.single.displayName, 'Ann Lee');
      expect((await get('group:a')).name, 'Ann Lee, +15551230002');
      expect((await get('group:b')).name, 'Family');

      final again = await chats.refreshImportedNames(importerUid: 'me', source: 'phone', lookup: book.lookup);
      expect(again, 0);
    });
  });

  test('findByPhones matches profiles by normalized number', () async {
    final db = FakeFirebaseFirestore();
    final users = UserRepository(db);
    await db.collection('users').doc('u1').set(
          const UserProfile(uid: 'u1', displayName: 'Ann', email: 'a@x.com').toMap(),
        );
    await users.updateProfile('u1', phone: '+1 (555) 123-0001');
    final found = await users.findByPhones(['555-123-0001', '5559990000'], excludeUid: 'me');
    expect(found.keys, ['5551230001']);
    expect(found['5551230001']!.uid, 'u1');
  });
}

class _FailingSink extends InMemoryImportSink {
  _FailingSink(this.failing);

  final String failing;

  @override
  Future<AppendResult> appendMessages(String threadKey, List<ImportedMessage> messages) {
    if (threadKey == failing) throw StateError('boom');
    return super.appendMessages(threadKey, messages);
  }
}

class _TwoThreads extends ImportSource {
  @override
  String get displayName => 'test';

  @override
  Future<void> read(ImportVisitor visitor,
      {required ReadOptions options, required CancellationToken token, ProgressCallback? onProgress}) async {
    for (final n in [1, 2, 3]) {
      final thread = ImportedThread(
        key: 'dm:$n',
        participants: [ImportedParticipant(address: '$n')],
        isGroup: false,
        service: MessageService.sms,
      );
      await visitor.onThread(thread);
      await visitor.onMessage(ImportedMessage(
        key: 'k$n',
        threadKey: thread.key,
        sentAt: DateTime.utc(2020),
        isFromMe: false,
        service: MessageService.sms,
        text: 'hi',
      ));
    }
  }
}
