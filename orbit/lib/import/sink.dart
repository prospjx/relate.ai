import 'models.dart';

class AppendResult {
  const AppendResult({required this.inserted, required this.skipped});

  final int inserted;

  /// Messages whose [ImportedMessage.key] already existed.
  final int skipped;
}

/// Destination for imported history. The core app implements this to write
/// into its own storage (local DB, Firestore, ...). The importer never sends
/// data anywhere else; where it goes after this call is up to the sink.
///
/// Contract:
/// * [upsertThread] is called before any messages of that thread and may be
///   called again for the same [ImportedThread.key] (merge, don't duplicate).
/// * [appendMessages] must be idempotent on [ImportedMessage.key]: keys that
///   already exist are skipped and counted in [AppendResult.skipped].
/// * Batches for one thread arrive in ascending [ImportedMessage.sentAt]
///   order within a batch, but batches for different threads may interleave.
/// * Attachment [ImportedAttachment.localPath] files live in the importer's
///   attachment folder; copy or upload them during [appendMessages] if the
///   app needs them elsewhere.
abstract class ImportSink {
  Future<void> begin(String sourceName) async {}

  Future<void> upsertThread(ImportedThread thread);

  Future<AppendResult> appendMessages(String threadKey, List<ImportedMessage> messages);

  Future<void> end(ImportSummary summary) async {}
}

/// Sink that keeps everything in memory. Used by tests and as a reference
/// implementation of the dedupe contract.
class InMemoryImportSink extends ImportSink {
  final Map<String, ImportedThread> threads = {};
  final Map<String, List<ImportedMessage>> messagesByThread = {};
  final Set<String> _keys = {};
  final List<String> begun = [];
  ImportSummary? lastSummary;

  int get messageCount => _keys.length;

  @override
  Future<void> begin(String sourceName) async => begun.add(sourceName);

  @override
  Future<void> upsertThread(ImportedThread thread) async {
    final existing = threads[thread.key];
    if (existing == null) {
      threads[thread.key] = thread;
      return;
    }
    final byAddress = {for (final p in existing.participants) p.address: p};
    for (final p in thread.participants) {
      byAddress[p.address] = p.displayName != null ? p : (byAddress[p.address] ?? p);
    }
    threads[thread.key] = existing.copyWith(
      participants: byAddress.values.toList(),
      title: thread.title,
    );
  }

  @override
  Future<AppendResult> appendMessages(String threadKey, List<ImportedMessage> messages) async {
    final list = messagesByThread.putIfAbsent(threadKey, () => []);
    var inserted = 0;
    for (final m in messages) {
      if (_keys.add(m.key)) {
        list.add(m);
        inserted++;
      }
    }
    list.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return AppendResult(inserted: inserted, skipped: messages.length - inserted);
  }

  @override
  Future<void> end(ImportSummary summary) async => lastSummary = summary;
}
