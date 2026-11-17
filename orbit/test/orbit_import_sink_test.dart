import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/data/chat_repository.dart';
import 'package:orbit/data/orbit_import_sink.dart';
import 'package:orbit/import/models.dart';
import 'package:orbit/models/models.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChatRepository chats;
  late OrbitImportSink sink;
  late List<String> uploads;

  const thread = ImportedThread(
    key: 'dm:+15550001',
    participants: [ImportedParticipant(address: '+15550001', displayName: 'Maya')],
    isGroup: false,
    service: MessageService.iMessage,
  );

  ImportedMessage msg(
    String key, {
    bool fromMe = false,
    String text = '',
    List<ImportedAttachment> attachments = const [],
    ImportedMessageKind kind = ImportedMessageKind.normal,
    String? target,
    String? reaction,
  }) =>
      ImportedMessage(
        key: key,
        threadKey: thread.key,
        sentAt: DateTime.utc(2024, 3, 1, 12, int.parse(key.replaceAll(RegExp(r'\D'), ''))),
        isFromMe: fromMe,
        senderAddress: fromMe ? null : '+15550001',
        service: MessageService.iMessage,
        text: text,
        attachments: attachments,
        kind: kind,
        reactionTargetKey: target,
        reaction: reaction,
      );

  setUp(() {
    db = FakeFirebaseFirestore();
    chats = ChatRepository(db, clock: () => DateTime(2026, 11, 17));
    uploads = [];
    sink = OrbitImportSink(
      chats: chats,
      importerUid: 'me',
      importerName: 'Me',
      readFile: (path) async {
        if (path.contains('missing')) throw StateError('gone');
        return Uint8List.fromList([1, 2, 3]);
      },
      upload: ({
        required conversationId,
        required kind,
        required bytes,
        required fileName,
        required mimeType,
      }) async {
        uploads.add(fileName);
        return Attachment(kind: kind, url: 'https://x/$fileName', name: fileName);
      },
    );
  });

  Future<List<Message>> stored() async {
    final id = ChatRepository.importedConversationId(
      importerUid: 'me',
      source: OrbitImportSink.source,
      externalKey: thread.key,
    );
    final snap = await chats.messagesOf(id).orderBy('sentAt').get();
    return snap.docs.map((d) => Message.fromMap(d.id, d.data())).toList();
  }

  test('writes text, splits attachments, and names external senders', () async {
    await sink.upsertThread(thread);
    final result = await sink.appendMessages(thread.key, [
      msg('m1', text: 'hi there'),
      msg('m2', fromMe: true, text: 'look', attachments: const [
        ImportedAttachment(fileName: 'a.jpg', mimeType: 'image/jpeg', localPath: '/a.jpg'),
        ImportedAttachment(fileName: 'b.mp4', mimeType: 'video/mp4', localPath: '/b.mp4'),
        ImportedAttachment(fileName: 'c.heic', mimeType: 'image/heic', missingReason: 'not in backup'),
      ]),
    ]);

    expect(result.inserted, 2);
    expect(result.skipped, 0);
    final messages = await stored();
    expect(messages.map((m) => m.kind), [
      MessageKind.text,
      MessageKind.text,
      MessageKind.image,
      MessageKind.video,
    ]);
    expect(messages.first.senderName, 'Maya');
    expect(messages.first.senderId, isNull);
    expect(messages[1].text, contains('Attachment not recovered: c.heic'));
    expect(messages[1].senderId, 'me');
    expect(messages.every((m) => m.imported), isTrue);
    expect(uploads, ['a.jpg', 'b.mp4']);
  });

  test('re-import skips existing messages without uploading again', () async {
    final batch = [
      msg('m1', attachments: const [
        ImportedAttachment(fileName: 'a.jpg', mimeType: 'image/jpeg', localPath: '/a.jpg'),
      ]),
    ];
    await sink.upsertThread(thread);
    await sink.appendMessages(thread.key, batch);
    uploads.clear();

    final again = await sink.appendMessages(thread.key, batch);
    expect(again.inserted, 0);
    expect(again.skipped, 1);
    expect(uploads, isEmpty);
    expect(await stored(), hasLength(1));
  });

  test('falls back to a note when a file cannot be read', () async {
    await sink.upsertThread(thread);
    await sink.appendMessages(thread.key, [
      msg('m1', attachments: const [
        ImportedAttachment(fileName: 'gone.png', mimeType: 'image/png', localPath: '/missing.png'),
      ]),
    ]);
    final only = (await stored()).single;
    expect(only.kind, MessageKind.text);
    expect(only.text, contains('could not be copied: gone.png'));
  });

  test('applies tapbacks, then removes them', () async {
    await sink.upsertThread(thread);
    await sink.appendMessages(thread.key, [
      msg('m1', fromMe: true, text: 'dinner?'),
      msg('m2', kind: ImportedMessageKind.reaction, target: 'm1', reaction: '❤️'),
    ]);
    var target = (await stored()).single;
    expect(target.reactions, {'ext:+15550001': '❤️'});

    await sink.appendMessages(thread.key, [
      ImportedMessage(
        key: 'm3',
        threadKey: thread.key,
        sentAt: DateTime.utc(2024, 3, 1, 13),
        isFromMe: false,
        senderAddress: '+15550001',
        service: MessageService.iMessage,
        kind: ImportedMessageKind.reaction,
        reactionTargetKey: 'm1',
        reaction: '❤️',
        reactionRemoved: true,
      ),
    ]);
    target = (await stored()).single;
    expect(target.reactions, isEmpty);
  });

  test('group threads get a name from participants when untitled', () async {
    await sink.upsertThread(const ImportedThread(
      key: 'grp:1',
      participants: [
        ImportedParticipant(address: '+1', displayName: 'Ana'),
        ImportedParticipant(address: '+2'),
      ],
      isGroup: true,
      service: MessageService.mms,
    ));
    final c = await chats.getConversation(ChatRepository.importedConversationId(
      importerUid: 'me',
      source: OrbitImportSink.source,
      externalKey: 'grp:1',
    ));
    expect(c!.type, ConversationType.group);
    expect(c.name, 'Ana, +2');
  });
}
