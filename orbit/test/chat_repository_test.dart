import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/chat_repository.dart';
import 'package:orbit/models/models.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChatRepository chats;
  late DateTime now;

  setUp(() {
    db = FakeFirebaseFirestore();
    now = DateTime(2026, 6, 1, 9);
    chats = ChatRepository(db, clock: () => now);
  });

  void tick([Duration by = const Duration(minutes: 1)]) => now = now.add(by);

  group('direct chats', () {
    test('openDirectChat is idempotent and order independent', () async {
      final a = await chats.openDirectChat(myUid: 'alice', otherUid: 'bob');
      final b = await chats.openDirectChat(myUid: 'bob', otherUid: 'alice');
      expect(a.id, b.id);
      expect(a.id, ChatRepository.directChatId('alice', 'bob'));
      final docs = await db.collection('conversations').get();
      expect(docs.docs, hasLength(1));
      expect(docs.docs.single.data()['memberIds'], ['alice', 'bob']);
    });

    test('sendMessage writes the message and bumps the inbox', () async {
      final c = await chats.openDirectChat(myUid: 'alice', otherUid: 'bob');
      tick();
      final m = await chats.sendMessage(
        conversationId: c.id,
        senderId: 'alice',
        senderName: 'Alice',
        text: '  hello  ',
      );
      expect(m.text, 'hello');

      final updated = (await chats.getConversation(c.id))!;
      expect(updated.lastMessage!.messageId, m.id);
      expect(updated.lastMessage!.preview, 'hello');
      expect(updated.updatedAt, now);
      expect(updated.hasUnreadFor('alice'), isFalse);
      expect(updated.hasUnreadFor('bob'), isTrue);

      tick();
      await chats.markRead(c.id, 'bob');
      expect((await chats.getConversation(c.id))!.hasUnreadFor('bob'), isFalse);
    });

    test('rejects empty text and attachment-less media', () async {
      final c = await chats.openDirectChat(myUid: 'a', otherUid: 'b');
      expect(
        () => chats.sendMessage(
            conversationId: c.id, senderId: 'a', senderName: 'A', text: ' '),
        throwsArgumentError,
      );
      expect(
        () => chats.sendMessage(
            conversationId: c.id,
            senderId: 'a',
            senderName: 'A',
            kind: MessageKind.image),
        throwsArgumentError,
      );
    });

    test('inbox lists only my conversations, newest first', () async {
      final older = await chats.openDirectChat(myUid: 'me', otherUid: 'x');
      tick();
      final newer = await chats.openDirectChat(myUid: 'me', otherUid: 'y');
      await chats.openDirectChat(myUid: 'p', otherUid: 'q');
      final inbox = await chats.watchInbox('me').first;
      expect(inbox.map((c) => c.id), [newer.id, older.id]);
    });
  });

  group('message changes', () {
    late Conversation c;
    late Message m;

    setUp(() async {
      c = await chats.openDirectChat(myUid: 'alice', otherUid: 'bob');
      m = await chats.sendMessage(
        conversationId: c.id,
        senderId: 'alice',
        senderName: 'Alice',
        text: 'first',
      );
    });

    Future<Message> reload() async {
      final snap = await chats.messagesOf(c.id).doc(m.id).get();
      return Message.fromMap(snap.id, snap.data()!, conversationId: c.id);
    }

    test('edit marks the message edited and refreshes the preview', () async {
      tick();
      await chats.editMessage(
          conversationId: c.id, messageId: m.id, text: 'fixed');
      final edited = await reload();
      expect(edited.text, 'fixed');
      expect(edited.edited, isTrue);
      expect((await chats.getConversation(c.id))!.lastMessage!.preview,
          'fixed');
    });

    test('delete for everyone leaves a tombstone', () async {
      await chats.setReaction(
          conversationId: c.id, messageId: m.id, uid: 'bob', emoji: '😂');
      await chats.deleteForEveryone(conversationId: c.id, messageId: m.id);
      final gone = await reload();
      expect(gone.deleted, isTrue);
      expect(gone.text, isEmpty);
      expect(gone.attachments, isEmpty);
      expect(gone.reactions, isEmpty);
      expect((await chats.getConversation(c.id))!.lastMessage!.preview,
          'Message deleted');
    });

    test('reactions toggle per person', () async {
      await chats.toggleReaction(m, 'bob', '👍');
      await chats.toggleReaction(m, 'alice', '👍');
      var current = await reload();
      expect(current.reactionGroups['👍'], unorderedEquals(['alice', 'bob']));

      await chats.toggleReaction(current, 'bob', '❤️');
      current = await reload();
      expect(current.reactions['bob'], '❤️');

      await chats.toggleReaction(current, 'bob', '❤️');
      current = await reload();
      expect(current.reactions.containsKey('bob'), isFalse);
      expect(current.reactions['alice'], '👍');
    });
  });

  test('watchMessages pages newest first', () async {
    final c = await chats.openDirectChat(myUid: 'a', otherUid: 'b');
    for (var i = 0; i < 5; i++) {
      tick();
      await chats.sendMessage(
          conversationId: c.id, senderId: 'a', senderName: 'A', text: 'm$i');
    }
    final page = await chats.watchMessages(c.id, limit: 3).first;
    expect(page.map((m) => m.text), ['m4', 'm3', 'm2']);
    final more = await chats.watchMessages(c.id, limit: 10).first;
    expect(more, hasLength(5));
  });

  group('groups', () {
    test('createGroup makes the creator admin and posts a system message',
        () async {
      final g = await chats.createGroup(
        creatorUid: 'a',
        creatorName: 'Ann',
        name: ' Trip ',
        memberIds: ['b', 'c', 'a'],
      );
      expect(g.name, 'Trip');
      expect(g.memberIds, unorderedEquals(['a', 'b', 'c']));
      expect(g.adminIds, ['a']);
      final messages = await chats.watchMessages(g.id).first;
      expect(messages.single.kind, MessageKind.system);
      expect(messages.single.text, 'Ann created the group');
      expect(g.hasUnreadFor('a'), isFalse);
      expect(g.hasUnreadFor('b'), isTrue);
    });

    test('requires a name and a member', () {
      expect(
        () => chats.createGroup(
            creatorUid: 'a', creatorName: 'A', name: '', memberIds: ['b']),
        throwsArgumentError,
      );
      expect(
        () => chats.createGroup(
            creatorUid: 'a', creatorName: 'A', name: 'X', memberIds: []),
        throwsArgumentError,
      );
    });

    test('add, remove, rename, and leave', () async {
      final g = await chats.createGroup(
          creatorUid: 'a', creatorName: 'A', name: 'G', memberIds: ['b']);
      await chats.addMembers(g.id, ['c', 'd']);
      await chats.removeMember(g.id, 'd');
      await chats.renameGroup(g.id, 'New name');
      var current = (await chats.getConversation(g.id))!;
      expect(current.memberIds, unorderedEquals(['a', 'b', 'c']));
      expect(current.name, 'New name');

      await chats.leaveGroup(g.id, 'a');
      current = (await chats.getConversation(g.id))!;
      expect(current.memberIds, unorderedEquals(['b', 'c']));
      expect(current.adminIds, hasLength(1),
          reason: 'the last admin leaving promotes someone');
      expect(current.memberIds, contains(current.adminIds.single));
    });
  });

  group('import', () {
    Message historical(String key, DateTime at,
            {String? senderId, String? address, String text = 'old'}) =>
        Message(
          id: '',
          conversationId: '',
          kind: MessageKind.text,
          sentAt: at,
          senderId: senderId,
          senderAddress: address,
          senderName: address ?? '',
          text: text,
          importKey: key,
        );

    test('writes history with original timestamps and senders, idempotently',
        () async {
      final c = await chats.upsertImportedConversation(
        importerUid: 'me',
        source: 'google_messages',
        externalKey: 'thread-7',
        participants: const [Participant(address: '+15550001111')],
      );
      final again = await chats.upsertImportedConversation(
        importerUid: 'me',
        source: 'google_messages',
        externalKey: 'thread-7',
        participants: const [
          Participant(address: '+15550001111', displayName: 'Dana'),
          Participant(address: '+15550002222'),
        ],
      );
      expect(again.id, c.id);
      expect(again.externalParticipants.map((p) => p.label),
          unorderedEquals(['Dana', '+15550002222']));

      final t1 = DateTime(2020, 1, 1, 8);
      final t2 = DateTime(2020, 1, 1, 9);
      final batch = [
        historical('sms-1', t1, address: '+15550001111', text: 'hey'),
        historical('sms-2', t2, senderId: 'me', text: 'hi back'),
      ];
      final result = await chats.importMessages(
        conversationId: c.id,
        importerUid: 'me',
        source: 'google_messages',
        messages: batch,
      );
      expect(result.written, 2);
      expect(result.skipped, 0);
      final rerun = await chats.importMessages(
        conversationId: c.id,
        importerUid: 'me',
        source: 'google_messages',
        messages: [
          ...batch,
          historical('sms-3', t2.add(const Duration(minutes: 1)),
              address: '+15550001111', text: 'later'),
        ],
      );
      expect(rerun.written, 1);
      expect(rerun.skipped, 2);

      final messages = await chats.watchMessages(c.id).first;
      expect(messages, hasLength(3), reason: 're-import must not duplicate');
      expect(messages[1].sentAt, t2);
      expect(messages[1].senderId, 'me');
      expect(messages.last.senderAddress, '+15550001111');
      expect(messages.last.senderId, isNull);
      expect(messages.every((m) => m.imported && m.importedBy == 'me'), isTrue);

      final updated = (await chats.getConversation(c.id))!;
      expect(updated.lastMessage!.preview, 'later');
      expect(updated.updatedAt, t2.add(const Duration(minutes: 1)));
      expect(updated.hasUnreadFor('me'), isFalse,
          reason: 'imported history is never unread');
      expect(updated.externalParticipants, hasLength(2));
    });

    test('older imports do not replace a newer last message', () async {
      final c = await chats.openDirectChat(myUid: 'me', otherUid: 'you');
      final live = await chats.sendMessage(
          conversationId: c.id, senderId: 'me', senderName: 'Me', text: 'now');
      await chats.importMessages(
        conversationId: c.id,
        importerUid: 'me',
        source: 'imessage',
        messages: [historical('x', DateTime(2019), senderId: 'me')],
      );
      final updated = (await chats.getConversation(c.id))!;
      expect(updated.lastMessage!.messageId, live.id);
    });

    test('rejects messages without a key or attributed to someone else', () {
      expect(
        () => chats.importMessages(
          conversationId: 'c',
          importerUid: 'me',
          source: 's',
          messages: [historical('', DateTime(2020))],
        ),
        throwsArgumentError,
      );
      expect(
        () => chats.importMessages(
          conversationId: 'c',
          importerUid: 'me',
          source: 's',
          messages: [historical('k', DateTime(2020), senderId: 'other')],
        ),
        throwsArgumentError,
      );
    });

    test('splits large imports across batches', () async {
      final c = await chats.upsertImportedConversation(
          importerUid: 'me', source: 's', externalKey: 'big');
      final base = DateTime(2018);
      final many = [
        for (var i = 0; i < ChatRepository.batchSize + 25; i++)
          historical('k$i', base.add(Duration(minutes: i)),
              address: 'a@b.c'),
      ];
      final result = await chats.importMessages(
          conversationId: c.id,
          importerUid: 'me',
          source: 's',
          messages: many);
      expect(result.written, many.length);
      final all = await chats.messagesOf(c.id).get();
      expect(all.docs, hasLength(many.length));
    });
  });
}
