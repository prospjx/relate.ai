import 'codec.dart';
import 'message.dart';
import 'participant.dart';

enum ConversationType { direct, group }

/// Denormalized summary of the newest message, kept on the conversation so
/// the inbox does not need to read message subcollections.
class LastMessage {
  const LastMessage({
    required this.messageId,
    required this.preview,
    required this.sentAt,
    this.senderId,
    this.senderName = '',
    this.kind = MessageKind.text,
  });

  final String messageId;
  final String preview;
  final DateTime sentAt;
  final String? senderId;
  final String senderName;
  final MessageKind kind;

  factory LastMessage.of(Message message) => LastMessage(
        messageId: message.id,
        preview: message.preview,
        sentAt: message.sentAt,
        senderId: message.senderId,
        senderName: message.senderLabel,
        kind: message.kind,
      );

  Map<String, Object?> toMap() => {
        'messageId': messageId,
        'preview': preview,
        'sentAt': writeDate(sentAt),
        'senderId': senderId,
        'senderName': senderName,
        'kind': kind.name,
      };

  static LastMessage? fromMap(Object? raw) {
    final map = readMap(raw);
    final id = map['messageId'] as String?;
    if (id == null) return null;
    return LastMessage(
      messageId: id,
      preview: map['preview'] as String? ?? '',
      sentAt: readDate(map['sentAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      senderId: map['senderId'] as String?,
      senderName: map['senderName'] as String? ?? '',
      kind: readEnum(MessageKind.values, map['kind'], MessageKind.text),
    );
  }
}

/// A chat stored at `conversations/{id}`.
class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.memberIds,
    required this.updatedAt,
    this.name = '',
    this.photoUrl,
    this.adminIds = const [],
    this.createdBy,
    this.createdAt,
    this.lastMessage,
    this.lastReadAt = const {},
    this.externalParticipants = const [],
    this.importSource,
    this.importKey,
  });

  final String id;
  final ConversationType type;

  /// Orbit uids allowed to read and write this conversation.
  final List<String> memberIds;
  final List<String> adminIds;
  final String name;
  final String? photoUrl;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime updatedAt;
  final LastMessage? lastMessage;

  /// uid -> time that member last read the conversation.
  final Map<String, DateTime> lastReadAt;

  /// People in imported history who are not Orbit users.
  final List<Participant> externalParticipants;
  final String? importSource;
  final String? importKey;

  bool get isGroup => type == ConversationType.group;

  bool isAdmin(String uid) => adminIds.contains(uid);

  /// The other member of a direct chat, or `null` for groups and self-chats.
  String? otherMemberId(String myUid) {
    if (isGroup) return null;
    for (final id in memberIds) {
      if (id != myUid) return id;
    }
    return null;
  }

  bool hasUnreadFor(String uid) {
    final last = lastMessage;
    if (last == null || last.senderId == uid) return false;
    final readAt = lastReadAt[uid];
    return readAt == null || last.sentAt.isAfter(readAt);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'memberIds': memberIds,
        'adminIds': adminIds,
        'name': name,
        'photoUrl': photoUrl,
        'createdBy': createdBy,
        'createdAt': writeDateOrNull(createdAt),
        'updatedAt': writeDate(updatedAt),
        'lastMessage': lastMessage?.toMap(),
        'lastReadAt': lastReadAt.map((k, v) => MapEntry(k, writeDate(v))),
        'externalParticipants':
            externalParticipants.map((p) => p.toMap()).toList(),
        'importSource': importSource,
        'importKey': importKey,
      };

  factory Conversation.fromMap(String id, Map<String, Object?> map) {
    final readAt = <String, DateTime>{};
    readMap(map['lastReadAt']).forEach((k, v) {
      final date = readDate(v);
      if (date != null) readAt[k] = date;
    });
    final external = map['externalParticipants'];
    return Conversation(
      id: id,
      type: readEnum(
        ConversationType.values,
        map['type'],
        ConversationType.direct,
      ),
      memberIds: readStringList(map['memberIds']),
      adminIds: readStringList(map['adminIds']),
      name: map['name'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      createdBy: map['createdBy'] as String?,
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']) ??
          readDate(map['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastMessage: LastMessage.fromMap(map['lastMessage']),
      lastReadAt: readAt,
      externalParticipants: external is Iterable
          ? external
              .whereType<Map>()
              .map((m) => Participant.fromMap(readMap(m)))
              .toList()
          : const [],
      importSource: map['importSource'] as String?,
      importKey: map['importKey'] as String?,
    );
  }
}
