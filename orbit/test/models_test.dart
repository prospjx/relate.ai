import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/models/codec.dart';
import 'package:orbit/models/models.dart';

void main() {
  final sent = DateTime(2026, 3, 4, 10, 30);

  group('Message', () {
    test('round-trips through a Firestore map', () {
      final message = Message(
        id: 'm1',
        conversationId: 'c1',
        kind: MessageKind.image,
        sentAt: sent,
        senderId: 'u1',
        senderName: 'Maya',
        text: 'Look',
        attachments: const [
          Attachment(
            kind: AttachmentKind.image,
            url: 'https://x/y.jpg',
            storagePath: 'chats/c1/u1/y.jpg',
            name: 'y.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 1200,
            width: 800,
            height: 600,
          ),
        ],
        editedAt: sent.add(const Duration(minutes: 1)),
        reactions: const {'u2': '👍', 'u3': '❤️'},
      );

      final map = message.toMap();
      expect(map['sentAt'], isA<Timestamp>());
      final back = Message.fromMap('m1', map);

      expect(back.kind, MessageKind.image);
      expect(back.sentAt, sent);
      expect(back.senderId, 'u1');
      expect(back.text, 'Look');
      expect(back.attachments.single.width, 800);
      expect(back.attachments.single.storagePath, 'chats/c1/u1/y.jpg');
      expect(back.edited, isTrue);
      expect(back.reactions, {'u2': '👍', 'u3': '❤️'});
    });

    test('keeps external sender identity for imported history', () {
      final message = Message(
        id: 'm2',
        conversationId: 'c1',
        kind: MessageKind.text,
        sentAt: sent,
        senderAddress: '+15551234567',
        text: 'hi',
        imported: true,
        importedBy: 'u1',
        importSource: 'google_messages',
        importKey: 'sms-42',
      );
      final back = Message.fromMap('m2', message.toMap());
      expect(back.senderId, isNull);
      expect(back.senderAddress, '+15551234567');
      expect(back.senderLabel, '+15551234567');
      expect(back.imported, isTrue);
      expect(back.importKey, 'sms-42');
    });

    test('tolerates missing and unknown fields', () {
      final back = Message.fromMap('m3', {'kind': 'hologram'});
      expect(back.kind, MessageKind.text);
      expect(back.text, '');
      expect(back.attachments, isEmpty);
      expect(back.reactions, isEmpty);
    });

    test('groups reactions by emoji, most popular first', () {
      final message = Message(
        id: 'm',
        conversationId: 'c',
        kind: MessageKind.text,
        sentAt: sent,
        reactions: const {'a': '😂', 'b': '👍', 'c': '👍'},
      );
      final groups = message.reactionGroups;
      expect(groups.keys.first, '👍');
      expect(groups['👍'], ['b', 'c']);
      expect(groups['😂'], ['a']);
    });

    test('previews describe media and tombstones', () {
      Message m(MessageKind kind, {bool deleted = false}) => Message(
            id: 'm',
            conversationId: 'c',
            kind: kind,
            sentAt: sent,
            deleted: deleted,
            attachments: const [
              Attachment(kind: AttachmentKind.document, name: 'plan.pdf'),
            ],
          );
      expect(m(MessageKind.audio).preview, 'Voice message');
      expect(m(MessageKind.document).preview, 'Document: plan.pdf');
      expect(m(MessageKind.sticker).preview, 'Sticker');
      expect(m(MessageKind.text, deleted: true).preview, 'Message deleted');
    });
  });

  group('Conversation', () {
    test('round-trips and computes unread state', () {
      final conversation = Conversation(
        id: 'c1',
        type: ConversationType.group,
        name: 'Climbing',
        memberIds: const ['u1', 'u2'],
        adminIds: const ['u1'],
        updatedAt: sent,
        lastMessage: LastMessage(
          messageId: 'm1',
          preview: 'hey',
          sentAt: sent,
          senderId: 'u1',
        ),
        lastReadAt: {'u1': sent},
        externalParticipants: const [
          Participant(address: 'ann@example.com', displayName: 'Ann'),
        ],
      );
      final back = Conversation.fromMap('c1', conversation.toMap());
      expect(back.isGroup, isTrue);
      expect(back.memberIds, ['u1', 'u2']);
      expect(back.isAdmin('u1'), isTrue);
      expect(back.lastMessage!.preview, 'hey');
      expect(back.externalParticipants.single.label, 'Ann');
      expect(back.hasUnreadFor('u1'), isFalse, reason: 'own message');
      expect(back.hasUnreadFor('u2'), isTrue, reason: 'never read');
    });

    test('finds the other member of a direct chat', () {
      final c = Conversation(
        id: 'dm',
        type: ConversationType.direct,
        memberIds: const ['a', 'b'],
        updatedAt: sent,
      );
      expect(c.otherMemberId('a'), 'b');
      expect(c.otherMemberId('b'), 'a');
    });
  });

  group('UserProfile', () {
    test('round-trips and stores lowercase search keys', () {
      const profile = UserProfile(
        uid: 'u1',
        displayName: 'Maya Chen',
        email: 'Maya@Example.com',
        about: 'Busy',
        phone: '+1555',
      );
      final map = profile.toMap();
      expect(map['displayNameLower'], 'maya chen');
      expect(map['emailLower'], 'maya@example.com');
      final back = UserProfile.fromMap('u1', map);
      expect(back.about, 'Busy');
      expect(back.phone, '+1555');
    });

    test('treats a stale heartbeat as offline', () {
      final now = DateTime(2026, 1, 1, 12);
      final fresh = UserProfile(
        uid: 'u',
        displayName: 'A',
        online: true,
        lastSeen: now.subtract(const Duration(seconds: 30)),
      );
      final stale = UserProfile(
        uid: 'u',
        displayName: 'A',
        online: true,
        lastSeen: now.subtract(const Duration(minutes: 10)),
      );
      expect(fresh.isOnlineAt(now), isTrue);
      expect(stale.isOnlineAt(now), isFalse);
    });
  });

  test('stableHash is deterministic and spreads inputs', () {
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
    expect(stableHash('abc'), hasLength(16));
  });

  test('readDate accepts several encodings', () {
    final d = DateTime(2025, 5, 6, 7, 8);
    expect(readDate(Timestamp.fromDate(d)), d);
    expect(readDate(d.millisecondsSinceEpoch), d);
    expect(readDate(d.toIso8601String()), d);
    expect(readDate(null), isNull);
  });
}
