import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core.dart';
import '../models.dart';
import '../util/address.dart';
import '../util/apple_time.dart';
import '../util/files.dart';
import '../util/sqlite.dart';
import '../util/typedstream.dart';

/// Maps the `attachment.filename` stored in the Messages database to a file
/// that exists on this machine.
abstract class AttachmentLocator {
  Future<File?> locate(String dbFilename);
}

/// macOS: `~/Library/Messages/Attachments/...`. Pass the Attachments folder
/// explicitly when chat.db was copied from another Mac/user.
class MacAttachmentLocator implements AttachmentLocator {
  MacAttachmentLocator(this.attachmentsRoot);

  final String attachmentsRoot;

  static const _prefixes = ['~/Library/Messages/Attachments/', 'Library/Messages/Attachments/'];

  @override
  Future<File?> locate(String dbFilename) async {
    for (final prefix in _prefixes) {
      final i = dbFilename.indexOf(prefix);
      if (i >= 0) {
        final rest = dbFilename.substring(i + prefix.length).split('/');
        final f = File(p.joinAll([attachmentsRoot, ...rest]));
        if (await f.exists()) return f;
      }
    }
    final direct = File(dbFilename);
    return await direct.exists() ? direct : null;
  }
}

const iMessageTapbacks = ['❤️', '👍', '👎', '😂', '‼️', '❓'];

/// Reads a Messages database: macOS `chat.db` or iOS `sms.db` (same schema).
/// Always works on a private copy of the file.
class IMessageDbSource extends ImportSource {
  IMessageDbSource({
    required this.dbPath,
    this.locator,
    String? displayName,
    this.pageSize = 500,
  }) : _displayName = displayName ?? 'iMessage database';

  final String dbPath;
  final AttachmentLocator? locator;
  final String _displayName;
  final int pageSize;
  Directory? _tempDir;

  @override
  String get displayName => _displayName;

  @override
  Future<void> dispose() async {
    final d = _tempDir;
    _tempDir = null;
    if (d != null && await d.exists()) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<void> read(
    ImportVisitor visitor, {
    required ReadOptions options,
    required CancellationToken token,
    ProgressCallback? onProgress,
  }) async {
    if (!await File(dbPath).exists()) {
      throw ImportException('File not found: $dbPath');
    }
    onProgress?.call(const ImportProgress(phase: 'Opening database', processed: 0));
    _tempDir ??= await Directory.systemTemp.createTemp('orbit_imessage_');
    final String copy;
    try {
      copy = await copySqliteForReading(dbPath, _tempDir!.path, name: 'messages.db');
    } on FileSystemException catch (e) {
      throw ImportException(
        'Could not read ${p.basename(dbPath)}: ${e.osError?.message ?? e.message}',
        hint: Platform.isMacOS
            ? 'On a Mac, give Orbit "Full Disk Access" in System Settings > Privacy & Security, then try again.'
            : null,
      );
    }

    // Our private copy is opened read-write so SQLite can apply a -wal journal.
    final SqliteDb db;
    try {
      db = SqliteDb.open(copy);
    } on SqliteException catch (e) {
      throw ImportException('This file could not be opened as a database (${e.message}).');
    }
    try {
      await _readDb(db, visitor, options, token, onProgress);
    } on SqliteException catch (e) {
      if (e.isNotADatabase) {
        throw const ImportException('This file is not a readable Messages database.',
            hint: 'If it came from an encrypted iPhone backup, make an unencrypted backup instead.');
      }
      throw ImportException('Error reading the Messages database: ${e.message}');
    } finally {
      db.close();
    }
  }

  Future<void> _readDb(
    SqliteDb db,
    ImportVisitor visitor,
    ReadOptions options,
    CancellationToken token,
    ProgressCallback? onProgress,
  ) async {
    for (final t in const ['message', 'handle', 'chat', 'chat_message_join']) {
      if (!tableExists(db, t)) {
        throw ImportException('This is not a Messages database (table "$t" is missing).',
            hint: 'Pick chat.db (Mac) or sms.db (iPhone backup).');
      }
    }
    final msgCols = tableColumns(db, 'message');
    final chatCols = tableColumns(db, 'chat');
    final hasAttachments = tableExists(db, 'attachment') && tableExists(db, 'message_attachment_join');
    final hasChatHandles = tableExists(db, 'chat_handle_join');

    final handles = <int, String>{
      for (final r in db.select('SELECT ROWID, id FROM handle'))
        (r['ROWID'] as int): (r['id'] as String? ?? ''),
    };

    final total = db.scalarInt('SELECT COUNT(*) FROM message') ?? 0;
    var processed = 0;
    var skippedEmpty = 0;

    String optional(String col, [String? alias]) =>
        msgCols.contains(col) ? 'm.$col AS ${alias ?? col}' : 'NULL AS ${alias ?? col}';
    final select = [
      'm.ROWID AS rowid',
      'm.guid AS guid',
      optional('text'),
      optional('attributedbody', 'attributedBody'),
      optional('handle_id'),
      optional('date'),
      optional('date_read'),
      optional('is_from_me'),
      optional('is_read'),
      optional('service'),
      optional('subject'),
      optional('item_type'),
      optional('group_title'),
      optional('associated_message_guid'),
      optional('associated_message_type'),
      optional('associated_message_emoji'),
      optional('cache_has_attachments'),
    ].join(', ');

    Future<void> emitPage(
      List<Map<String, Object?>> rows,
      ImportedThread thread,
    ) async {
      // SQLite calls are synchronous; yield so the UI stays responsive.
      await Future<void>.delayed(Duration.zero);
      final attachmentsByMessage = hasAttachments
          ? await _attachmentsFor(db, rows.map((r) => r['rowid'] as int).toList(), options)
          : const <int, List<ImportedAttachment>>{};
      for (final r in rows) {
        token.throwIfCancelled();
        processed++;
        final m = _mapMessage(r, thread, handles, attachmentsByMessage[r['rowid'] as int] ?? const [], visitor);
        if (m == null) {
          skippedEmpty++;
        } else {
          await visitor.onMessage(m);
        }
      }
      onProgress?.call(ImportProgress(
        phase: 'Reading messages',
        processed: processed,
        total: total,
        detail: thread.title ?? thread.participants.map((x) => x.address).join(', '),
      ));
    }

    // Chats.
    final chats = db.select(
      'SELECT ROWID, guid, chat_identifier, '
      '${chatCols.contains('service_name') ? 'service_name' : 'NULL AS service_name'}, '
      '${chatCols.contains('display_name') ? 'display_name' : 'NULL AS display_name'}, '
      '${chatCols.contains('style') ? 'style' : 'NULL AS style'} FROM chat',
    );
    for (final chat in chats) {
      token.throwIfCancelled();
      final chatId = chat['ROWID'] as int;
      final members = hasChatHandles
          ? [
              for (final r in db.select(
                  'SELECT handle_id FROM chat_handle_join WHERE chat_id = ? ORDER BY handle_id', [chatId]))
                if (handles[r['handle_id']] case final String a when a.isNotEmpty) a,
            ]
          : <String>[];
      final identifier = chat['chat_identifier'] as String? ?? '';
      if (members.isEmpty && identifier.isNotEmpty && !identifier.startsWith('chat')) {
        members.add(identifier);
      }
      final style = chat['style'] as int?;
      final isGroup = style == 43 || members.length > 1 || (style == null && identifier.startsWith('chat'));
      final displayName = (chat['display_name'] as String?)?.trim();
      final thread = ImportedThread(
        key: isGroup
            ? 'imsg-group:${identifier.isNotEmpty ? identifier : chat['guid']}'
            : directThreadKey(members.isNotEmpty ? members.first : identifier),
        participants: [for (final a in members.toSet()) ImportedParticipant(address: a)],
        isGroup: isGroup,
        service: _service(chat['service_name'] as String?, false),
        title: (displayName == null || displayName.isEmpty) ? null : displayName,
        sourceId: chat['guid'] as String?,
      );
      if (thread.participants.isEmpty && !isGroup) continue;
      await visitor.onThread(thread);

      for (var offset = 0;; offset += pageSize) {
        final rows = db.select(
          'SELECT $select FROM message m JOIN chat_message_join cmj ON cmj.message_id = m.ROWID '
          'WHERE cmj.chat_id = ? ORDER BY m.date, m.ROWID LIMIT ? OFFSET ?',
          [chatId, pageSize, offset],
        );
        if (rows.isEmpty) break;
        await emitPage(rows, thread);
        if (rows.length < pageSize) break;
      }
    }

    // Messages not attached to any chat (seen in some older/partial DBs):
    // group them into 1:1 threads by handle.
    final announced = <String>{};
    for (var offset = 0;; offset += pageSize) {
      token.throwIfCancelled();
      final rows = db.select(
        'SELECT $select FROM message m WHERE m.ROWID NOT IN (SELECT message_id FROM chat_message_join) '
        'ORDER BY m.handle_id, m.date, m.ROWID LIMIT ? OFFSET ?',
        [pageSize, offset],
      );
      if (rows.isEmpty) break;
      final byHandle = <String, List<Map<String, Object?>>>{};
      for (final r in rows) {
        final address = handles[r['handle_id']] ?? '';
        if (address.isEmpty) {
          processed++;
          skippedEmpty++;
          continue;
        }
        byHandle.putIfAbsent(address, () => []).add(r);
      }
      for (final entry in byHandle.entries) {
        final thread = ImportedThread(
          key: directThreadKey(entry.key),
          participants: [ImportedParticipant(address: entry.key)],
          isGroup: false,
          service: _service(entry.value.first['service'] as String?, false),
        );
        if (announced.add(thread.key)) await visitor.onThread(thread);
        await emitPage(entry.value, thread);
      }
      if (rows.length < pageSize) break;
    }

    if (skippedEmpty > 0) {
      visitor.onIssue(ImportIssue(
        '$skippedEmpty items had no text or attachments (app/game messages, unsent messages, '
        'membership events) and were skipped.',
      ));
    }
  }

  ImportedMessage? _mapMessage(
    Map<String, Object?> r,
    ImportedThread thread,
    Map<int, String> handles,
    List<ImportedAttachment> attachments,
    ImportVisitor visitor,
  ) {
    final guid = r['guid'] as String? ?? 'rowid-${r['rowid']}';
    final sentAt = appleTimestampToDateTime(r['date'] as num?);
    if (sentAt == null) {
      visitor.onIssue(ImportIssue('Message without a date skipped', context: guid));
      return null;
    }
    final isFromMe = (r['is_from_me'] as int? ?? 0) == 1;
    String? sender;
    if (!isFromMe) {
      sender = handles[r['handle_id']];
      if ((sender == null || sender.isEmpty) && !thread.isGroup && thread.participants.isNotEmpty) {
        sender = thread.participants.first.address;
      }
    }
    final service = _service(r['service'] as String?, attachments.isNotEmpty);
    final readAt = appleTimestampToDateTime(r['date_read'] as num?);
    final isRead = isFromMe || (r['is_read'] as int? ?? 0) == 1 || readAt != null;

    final assocType = r['associated_message_type'] as int? ?? 0;
    if (assocType >= 2000 && assocType < 4000) {
      final removed = assocType >= 3000;
      final index = assocType % 1000;
      final target = _parseAssociatedGuid(r['associated_message_guid'] as String?);
      if (target == null || index > 7) return null;
      final reaction = index < iMessageTapbacks.length
          ? iMessageTapbacks[index]
          : index == 6
              ? (r['associated_message_emoji'] as String? ?? '🙂')
              : 'sticker';
      return ImportedMessage(
        key: 'imsg:$guid',
        threadKey: thread.key,
        sentAt: sentAt,
        isFromMe: isFromMe,
        senderAddress: sender,
        service: service,
        kind: ImportedMessageKind.reaction,
        reactionTargetKey: 'imsg:$target',
        reaction: reaction,
        reactionRemoved: removed,
        isRead: isRead,
        readAt: readAt,
      );
    }
    // Stickers (1000), poll votes (4000) and other app payloads.
    if ((assocType == 1000 || assocType >= 4000) && attachments.isEmpty) return null;

    final itemType = r['item_type'] as int? ?? 0;
    if (itemType != 0) {
      final title = (r['group_title'] as String?)?.trim();
      if (itemType == 2 && title != null && title.isNotEmpty) {
        return ImportedMessage(
          key: 'imsg:$guid',
          threadKey: thread.key,
          sentAt: sentAt,
          isFromMe: isFromMe,
          senderAddress: sender,
          service: service,
          kind: ImportedMessageKind.system,
          text: 'Named the conversation "$title"',
        );
      }
      return null;
    }

    var text = r['text'] as String?;
    if (text == null || text.replaceAll('\uFFFC', '').trim().isEmpty) {
      final blob = r['attributedBody'];
      final extracted = extractAttributedBodyText(blob is Uint8List ? blob : (blob is List<int> ? Uint8List.fromList(blob) : null));
      if (extracted != null) text = extracted;
    }
    text = (text ?? '').replaceAll('\uFFFC', '').replaceAll('\uFFFD', '').trim();
    if (text.isEmpty && attachments.isEmpty) return null;
    final subject = (r['subject'] as String?)?.trim();

    return ImportedMessage(
      key: 'imsg:$guid',
      threadKey: thread.key,
      sentAt: sentAt,
      isFromMe: isFromMe,
      senderAddress: sender,
      service: service,
      text: text,
      attachments: attachments,
      isRead: isRead,
      readAt: readAt,
      subject: (subject == null || subject.isEmpty) ? null : subject,
    );
  }

  Future<Map<int, List<ImportedAttachment>>> _attachmentsFor(
    SqliteDb db,
    List<int> messageIds,
    ReadOptions options,
  ) async {
    if (messageIds.isEmpty) return const {};
    final rows = db.select(
      'SELECT maj.message_id AS message_id, a.guid AS guid, a.filename AS filename, a.mime_type AS mime_type, '
      'a.transfer_name AS transfer_name, a.total_bytes AS total_bytes '
      'FROM message_attachment_join maj JOIN attachment a ON a.ROWID = maj.attachment_id '
      'WHERE maj.message_id IN (${List.filled(messageIds.length, '?').join(',')}) ORDER BY a.ROWID',
      messageIds,
    );
    final result = <int, List<ImportedAttachment>>{};
    for (final r in rows) {
      final dbFilename = r['filename'] as String?;
      final transfer = r['transfer_name'] as String? ?? dbFilename?.split('/').last;
      if (transfer != null && transfer.endsWith('.pluginPayloadAttachment')) continue;
      final mime = (r['mime_type'] as String?) ?? guessMimeType(transfer ?? '');
      final name = safeFileName(transfer, mime);
      final size = (r['total_bytes'] as num?)?.toInt();
      String? localPath;
      String? missing;
      if (dbFilename == null || dbFilename.isEmpty) {
        missing = 'No file recorded (never downloaded)';
      } else if (locator == null) {
        missing = 'Attachment folder not available';
      } else {
        final file = await locator!.locate(dbFilename);
        if (file == null) {
          missing = 'File not found (may be stored only in iCloud)';
        } else if (options.extractAttachments && options.attachmentDirectory != null) {
          final guid = r['guid'] as String? ?? dbFilename;
          localPath = await copyIfChanged(
            file,
            p.join(options.attachmentDirectory!, '${stableHash([guid])}_$name'),
          );
        } else {
          localPath = file.path;
        }
      }
      result.putIfAbsent(r['message_id'] as int, () => []).add(ImportedAttachment(
            fileName: name,
            mimeType: mime,
            localPath: localPath,
            sizeBytes: size,
            missingReason: missing,
          ));
    }
    return result;
  }

  static String? _parseAssociatedGuid(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final slash = raw.indexOf('/');
    if (slash >= 0) return raw.substring(slash + 1);
    final colon = raw.indexOf(':');
    if (colon >= 0) return raw.substring(colon + 1);
    return raw;
  }

  static MessageService _service(String? raw, bool hasAttachments) {
    final s = (raw ?? '').toLowerCase();
    if (s.contains('imessage')) return MessageService.iMessage;
    if (s == 'rcs') return MessageService.rcs;
    if (s == 'sms' || s == 'mms') return hasAttachments ? MessageService.mms : MessageService.sms;
    return MessageService.unknown;
  }
}
