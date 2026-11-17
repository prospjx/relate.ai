import 'core.dart';
import 'models.dart';
import 'sink.dart';
import 'util/contacts.dart';

/// Runs an [ImportSource] into a preview or an [ImportSink].
class ImportEngine {
  ImportEngine({this.batchSize = 250, this.contacts, this.maxIssues = 200});

  final int batchSize;

  /// Optional address -> name lookup (e.g. from a .vcf) applied to
  /// participants that have no name.
  final ContactBook? contacts;
  final int maxIssues;

  /// Reads the whole source without writing anything or extracting files.
  Future<ImportPreview> preview(
    ImportSource source, {
    ReadOptions options = const ReadOptions(),
    CancellationToken? token,
    ProgressCallback? onProgress,
  }) async {
    final preview = ImportPreview();
    final visitor = _PreviewVisitor(preview, maxIssues);
    await source.read(
      visitor,
      options: options.copyWith(extractAttachments: false),
      token: token ?? CancellationToken(),
      onProgress: onProgress,
    );
    return preview;
  }

  /// Imports everything. Never throws: fatal problems, cancellation and
  /// per-item issues are reported in the returned [ImportSummary]. Messages
  /// read before a cancel or failure are still written (re-running is safe
  /// because sinks dedupe on message keys).
  Future<ImportSummary> run(
    ImportSource source,
    ImportSink sink, {
    ReadOptions options = const ReadOptions(),
    CancellationToken? token,
    ProgressCallback? onProgress,
  }) async {
    final summary = ImportSummary(sourceName: source.displayName);
    final stopwatch = Stopwatch()..start();
    final visitor = _SinkVisitor(sink, summary, batchSize, contacts, maxIssues);
    await sink.begin(source.displayName);
    try {
      await source.read(visitor, options: options, token: token ?? CancellationToken(), onProgress: onProgress);
    } on ImportCancelled {
      summary.cancelled = true;
    } on ImportException catch (e) {
      summary.fatalError = e.toString();
    } catch (e) {
      summary.fatalError = 'Unexpected error while reading ${source.displayName}: $e';
    }
    try {
      onProgress?.call(ImportProgress(phase: 'Saving', processed: summary.messagesAdded));
      await visitor.flushAll();
    } catch (e) {
      summary.fatalError ??= 'Could not save imported messages: $e';
    }
    stopwatch.stop();
    summary.elapsed = stopwatch.elapsed;
    await sink.end(summary);
    return summary;
  }
}

void _addIssue(List<ImportIssue> issues, ImportIssue issue, int max) {
  if (issues.length < max) {
    issues.add(issue);
  } else if (issues.length == max) {
    issues.add(const ImportIssue('More issues were found but not listed.'));
  }
}

class _PreviewVisitor implements ImportVisitor {
  _PreviewVisitor(this.preview, this.maxIssues);

  final ImportPreview preview;
  final int maxIssues;
  final Set<String> _threads = {};

  @override
  Future<void> onThread(ImportedThread thread) async {
    if (_threads.add(thread.key)) {
      preview.threads++;
      if (thread.isGroup) preview.groupThreads++;
    }
  }

  @override
  Future<void> onMessage(ImportedMessage message) async => preview.addMessage(message);

  @override
  void onIssue(ImportIssue issue) => _addIssue(preview.issues, issue, maxIssues);
}

class _SinkVisitor implements ImportVisitor {
  _SinkVisitor(this.sink, this.summary, this.batchSize, this.contacts, this.maxIssues);

  final ImportSink sink;
  final ImportSummary summary;
  final int batchSize;
  final ContactBook? contacts;
  final int maxIssues;
  final Set<String> _threads = {};
  final Map<String, List<ImportedMessage>> _buffers = {};

  @override
  Future<void> onThread(ImportedThread thread) async {
    final named = contacts == null
        ? thread
        : thread.copyWith(participants: [
            for (final p in thread.participants) p.displayName == null ? p.withName(contacts!.lookup(p.address)) : p,
          ]);
    if (_threads.add(thread.key)) summary.threads++;
    await sink.upsertThread(named);
  }

  @override
  Future<void> onMessage(ImportedMessage message) async {
    final buffer = _buffers.putIfAbsent(message.threadKey, () => []);
    buffer.add(message);
    if (buffer.length >= batchSize) await _flush(message.threadKey);
  }

  @override
  void onIssue(ImportIssue issue) => _addIssue(summary.issues, issue, maxIssues);

  Future<void> _flush(String threadKey) async {
    final batch = _buffers.remove(threadKey);
    if (batch == null || batch.isEmpty) return;
    batch.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final result = await sink.appendMessages(threadKey, batch);
    summary.messagesAdded += result.inserted;
    summary.duplicatesSkipped += result.skipped;
    for (final m in batch) {
      for (final a in m.attachments) {
        if (a.localPath != null) {
          summary.attachments++;
        } else {
          summary.missingAttachments++;
        }
      }
    }
  }

  Future<void> flushAll() async {
    for (final key in _buffers.keys.toList()) {
      await _flush(key);
    }
  }
}
