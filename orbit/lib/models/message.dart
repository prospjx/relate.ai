import 'attachment.dart';
import 'codec.dart';

enum MessageKind { text, image, video, audio, document, gif, sticker, system }

/// Reactions offered in the picker. Any single emoji is accepted in data.
const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// A message stored at `conversations/{conversationId}/messages/{id}`.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.kind,
    required this.sentAt,
    this.senderId,
    this.senderAddress,
    this.senderName = '',
    this.text = '',
    this.attachments = const [],
    this.editedAt,
    this.deleted = false,
    this.deletedAt,
    this.reactions = const {},
    this.imported = false,
    this.importedBy,
    this.importSource,
    this.importKey,
  });

  final String id;
  final String conversationId;
  final MessageKind kind;

  /// When the message was originally sent. For imports this is the original
  /// timestamp from the source app.
  final DateTime sentAt;

  /// Orbit uid of the sender, or `null` for a sender who is not an Orbit user
  /// (imported history), in which case [senderAddress] identifies them.
  final String? senderId;
  final String? senderAddress;
  final String senderName;
  final String text;
  final List<Attachment> attachments;
  final DateTime? editedAt;
  final bool deleted;
  final DateTime? deletedAt;

  /// Reactor key (uid) -> emoji. One reaction per person.
  final Map<String, String> reactions;

  final bool imported;
  final String? importedBy;
  final String? importSource;
  final String? importKey;

  bool get edited => editedAt != null && !deleted;

  bool isFrom(String uid) => senderId == uid;

  /// Emoji -> reactor keys, ordered by count then by first appearance.
  Map<String, List<String>> get reactionGroups {
    final groups = <String, List<String>>{};
    for (final entry in reactions.entries) {
      groups.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    final sorted = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return {for (final e in sorted) e.key: e.value};
  }

  String get senderLabel {
    if (senderName.trim().isNotEmpty) return senderName;
    return senderAddress ?? 'Unknown';
  }

  /// One-line summary for the inbox and notifications.
  String get preview {
    if (deleted) return 'Message deleted';
    switch (kind) {
      case MessageKind.text:
      case MessageKind.system:
        return text;
      case MessageKind.image:
        return text.isNotEmpty ? 'Photo: $text' : 'Photo';
      case MessageKind.video:
        return text.isNotEmpty ? 'Video: $text' : 'Video';
      case MessageKind.audio:
        return 'Voice message';
      case MessageKind.document:
        final name = attachments.isNotEmpty ? attachments.first.name : null;
        return name == null ? 'Document' : 'Document: $name';
      case MessageKind.gif:
        return 'GIF';
      case MessageKind.sticker:
        return 'Sticker';
    }
  }

  Message copyWith({
    String? text,
    DateTime? editedAt,
    bool? deleted,
    DateTime? deletedAt,
    List<Attachment>? attachments,
    Map<String, String>? reactions,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      kind: kind,
      sentAt: sentAt,
      senderId: senderId,
      senderAddress: senderAddress,
      senderName: senderName,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      editedAt: editedAt ?? this.editedAt,
      deleted: deleted ?? this.deleted,
      deletedAt: deletedAt ?? this.deletedAt,
      reactions: reactions ?? this.reactions,
      imported: imported,
      importedBy: importedBy,
      importSource: importSource,
      importKey: importKey,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'kind': kind.name,
        'sentAt': writeDate(sentAt),
        'senderId': senderId,
        'senderAddress': senderAddress,
        'senderName': senderName,
        'text': text,
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'editedAt': writeDateOrNull(editedAt),
        'deleted': deleted,
        'deletedAt': writeDateOrNull(deletedAt),
        'reactions': reactions,
        'imported': imported,
        'importedBy': importedBy,
        'importSource': importSource,
        'importKey': importKey,
      };

  factory Message.fromMap(
    String id,
    Map<String, Object?> map, {
    String? conversationId,
  }) {
    final rawAttachments = map['attachments'];
    return Message(
      id: id,
      conversationId: conversationId ?? map['conversationId'] as String? ?? '',
      kind: readEnum(MessageKind.values, map['kind'], MessageKind.text),
      sentAt: readDate(map['sentAt']) ??
          readDate(map['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      senderId: map['senderId'] as String?,
      senderAddress: map['senderAddress'] as String?,
      senderName: map['senderName'] as String? ?? '',
      text: map['text'] as String? ?? '',
      attachments: rawAttachments is Iterable
          ? rawAttachments
              .whereType<Map>()
              .map((m) => Attachment.fromMap(readMap(m)))
              .toList()
          : const [],
      editedAt: readDate(map['editedAt']),
      deleted: map['deleted'] as bool? ?? false,
      deletedAt: readDate(map['deletedAt']),
      reactions: readMap(map['reactions'])
          .map((k, v) => MapEntry(k, v?.toString() ?? ''))
        ..removeWhere((_, v) => v.isEmpty),
      imported: map['imported'] as bool? ?? false,
      importedBy: map['importedBy'] as String?,
      importSource: map['importSource'] as String?,
      importKey: map['importKey'] as String?,
    );
  }
}
