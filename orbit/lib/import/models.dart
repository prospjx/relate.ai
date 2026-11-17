/// Source-neutral intermediate model for imported chat history.
///
/// Every importer (iMessage chat.db / sms.db, iPhone backup, SMS Backup &
/// Restore XML, Android on-device) produces these types; the core app turns
/// them into its own conversations/messages through an [ImportSink].
library;

enum MessageService { sms, mms, rcs, iMessage, unknown }

enum ImportedMessageKind {
  /// A normal message with text and/or attachments.
  normal,

  /// A tapback / reaction pointing at another message ([ImportedMessage.reactionTargetKey]).
  reaction,

  /// A conversation event such as a group rename.
  system,
}

class ImportedParticipant {
  const ImportedParticipant({
    required this.address,
    this.displayName,
  });

  /// Phone number (as stored by the source) or email / Apple ID.
  final String address;

  /// Name from the source or from contact resolution, if known.
  final String? displayName;

  ImportedParticipant withName(String? name) =>
      ImportedParticipant(address: address, displayName: name ?? displayName);

  @override
  String toString() => displayName == null ? address : '$displayName <$address>';
}

class ImportedThread {
  const ImportedThread({
    required this.key,
    required this.participants,
    required this.isGroup,
    required this.service,
    this.title,
    this.sourceId,
  });

  /// Stable key used for dedupe across re-imports. 1:1 threads use
  /// `dm:<normalized address>` so the same person from different sources
  /// lands in the same conversation.
  final String key;

  /// The other people in the conversation (never includes the device owner).
  final List<ImportedParticipant> participants;
  final bool isGroup;
  final MessageService service;

  /// Group name, if the source has one.
  final String? title;

  /// Source-native identifier (e.g. iMessage chat guid), informational only.
  final String? sourceId;

  ImportedThread copyWith({List<ImportedParticipant>? participants, String? title}) {
    return ImportedThread(
      key: key,
      participants: participants ?? this.participants,
      isGroup: isGroup,
      service: service,
      title: title ?? this.title,
      sourceId: sourceId,
    );
  }
}

class ImportedAttachment {
  const ImportedAttachment({
    required this.fileName,
    required this.mimeType,
    this.localPath,
    this.sizeBytes,
    this.missingReason,
  });

  final String fileName;
  final String mimeType;

  /// Path to a readable local copy. Null when the file could not be
  /// recovered (see [missingReason]) or during a preview, where files are
  /// not extracted.
  final String? localPath;
  final int? sizeBytes;

  /// Why the file could not be recovered (e.g. "not in backup", "media not
  /// included"); null when it is (or, in a preview, will be) available.
  final String? missingReason;

  bool get isAvailable => missingReason == null;
}

class ImportedMessage {
  const ImportedMessage({
    required this.key,
    required this.threadKey,
    required this.sentAt,
    required this.isFromMe,
    required this.service,
    this.senderAddress,
    this.text = '',
    this.attachments = const [],
    this.isRead = true,
    this.readAt,
    this.kind = ImportedMessageKind.normal,
    this.reactionTargetKey,
    this.reaction,
    this.reactionRemoved = false,
    this.subject,
  });

  /// Stable dedupe key. Re-importing the same data always yields the same key.
  final String key;
  final String threadKey;

  /// Original timestamp in UTC.
  final DateTime sentAt;
  final bool isFromMe;

  /// Sender address for incoming messages; null when [isFromMe].
  final String? senderAddress;
  final MessageService service;
  final String text;
  final List<ImportedAttachment> attachments;
  final bool isRead;
  final DateTime? readAt;
  final ImportedMessageKind kind;

  /// For reactions: [key] of the message being reacted to.
  final String? reactionTargetKey;

  /// For reactions: emoji or name such as "❤️", "👍".
  final String? reaction;

  /// For reactions: true when this row removes an earlier reaction.
  final bool reactionRemoved;
  final String? subject;
}

/// Counts shown to the user before confirming an import.
class ImportPreview {
  ImportPreview();

  int threads = 0;
  int groupThreads = 0;
  int messages = 0;
  int reactions = 0;
  int attachments = 0;
  int missingAttachments = 0;
  DateTime? earliest;
  DateTime? latest;
  final Map<MessageService, int> byService = {};
  final List<ImportIssue> issues = [];

  void addMessage(ImportedMessage m) {
    if (m.kind == ImportedMessageKind.reaction) {
      reactions++;
    } else {
      messages++;
    }
    byService[m.service] = (byService[m.service] ?? 0) + 1;
    for (final a in m.attachments) {
      attachments++;
      if (!a.isAvailable) missingAttachments++;
    }
    if (earliest == null || m.sentAt.isBefore(earliest!)) earliest = m.sentAt;
    if (latest == null || m.sentAt.isAfter(latest!)) latest = m.sentAt;
  }
}

enum ImportIssueSeverity { warning, error }

class ImportIssue {
  const ImportIssue(this.message, {this.severity = ImportIssueSeverity.warning, this.context});

  final String message;
  final ImportIssueSeverity severity;

  /// Where it happened, e.g. "message 1234" or "line 88".
  final String? context;

  @override
  String toString() => context == null ? message : '$message ($context)';
}

class ImportProgress {
  const ImportProgress({
    required this.phase,
    required this.processed,
    this.total,
    this.detail,
  });

  final String phase;
  final int processed;

  /// Null when the total is unknown (e.g. while streaming XML).
  final int? total;
  final String? detail;

  double? get fraction =>
      total == null || total == 0 ? null : (processed / total!).clamp(0.0, 1.0);
}

class ImportSummary {
  ImportSummary({required this.sourceName});

  final String sourceName;
  int threads = 0;
  int messagesAdded = 0;
  int duplicatesSkipped = 0;
  int attachments = 0;
  int missingAttachments = 0;
  bool cancelled = false;
  String? fatalError;
  Duration elapsed = Duration.zero;
  final List<ImportIssue> issues = [];

  bool get succeeded => fatalError == null && !cancelled;
}
