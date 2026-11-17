import 'models.dart';

class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ImportCancelled();
  }
}

class ImportCancelled implements Exception {
  const ImportCancelled();

  @override
  String toString() => 'Import cancelled';
}

/// A fatal, user-presentable problem with a source (wrong file, encrypted
/// backup, missing permission...).
class ImportException implements Exception {
  const ImportException(this.message, {this.hint});

  final String message;

  /// What the user can do about it.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}

typedef ProgressCallback = void Function(ImportProgress progress);

/// Receives data from a source. Threads are always announced before their
/// first message.
abstract class ImportVisitor {
  Future<void> onThread(ImportedThread thread);

  Future<void> onMessage(ImportedMessage message);

  void onIssue(ImportIssue issue);
}

class ReadOptions {
  const ReadOptions({
    this.extractAttachments = true,
    this.attachmentDirectory,
    this.ownAddresses = const {},
  });

  /// When false (preview), sources only report attachment metadata and do not
  /// write or copy files.
  final bool extractAttachments;

  /// Where recovered attachment files are written. Required when
  /// [extractAttachments] is true for sources that need to copy/decode files.
  final String? attachmentDirectory;

  /// The device owner's own phone numbers/emails, used to drop "me" from
  /// group participant lists in sources that include it.
  final Set<String> ownAddresses;

  ReadOptions copyWith({bool? extractAttachments}) => ReadOptions(
        extractAttachments: extractAttachments ?? this.extractAttachments,
        attachmentDirectory: attachmentDirectory,
        ownAddresses: ownAddresses,
      );
}

abstract class ImportSource {
  /// Human-readable name shown in UI and summaries.
  String get displayName;

  /// Streams all threads and messages into [visitor]. Must check [token]
  /// regularly and throw [ImportCancelled] when cancelled; throws
  /// [ImportException] for fatal source problems. Must not upload anything.
  Future<void> read(
    ImportVisitor visitor, {
    required ReadOptions options,
    required CancellationToken token,
    ProgressCallback? onProgress,
  });

  /// Releases temp files (copied databases etc.).
  Future<void> dispose() async {}
}
