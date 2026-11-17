import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/codec.dart';
import '../models/models.dart';

/// Result of [ChatRepository.importMessages].
class ImportResult {
  const ImportResult({required this.written, this.skipped = 0, this.newest});

  final int written;

  /// Messages whose import key was already stored (only with skipExisting).
  final int skipped;
  final Message? newest;
}

/// Conversations at `conversations/{id}` and messages at
/// `conversations/{id}/messages/{messageId}`.
class ChatRepository {
  ChatRepository(this._db, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  static const conversationsCollection = 'conversations';
  static const messagesCollection = 'messages';

  /// Firestore allows 500 writes per batch; leave room for the summary write.
  static const batchSize = 400;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection(conversationsCollection);

  CollectionReference<Map<String, dynamic>> messagesOf(String conversationId) =>
      _conversations.doc(conversationId).collection(messagesCollection);

  static String directChatId(String a, String b) {
    final ids = [a, b]..sort();
    return 'dm_${ids[0]}_${ids[1]}';
  }

  /// Deterministic id so re-running an import reuses the same conversation.
  static String importedConversationId({
    required String importerUid,
    required String source,
    required String externalKey,
  }) =>
      'imp_${stableHash('$importerUid|$source|$externalKey')}';

  /// Deterministic id so re-running an import overwrites instead of
  /// duplicating.
  static String importedMessageId({
    required String source,
    required String importKey,
  }) =>
      'imp_${stableHash('$source|$importKey')}';

  // Conversations

  Stream<List<Conversation>> watchInbox(String uid) {
    return _conversations
        .where('memberIds', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Conversation.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<Conversation?> watchConversation(String id) {
    return _conversations.doc(id).snapshots().map(
          (s) => s.exists ? Conversation.fromMap(s.id, s.data()!) : null,
        );
  }

  Future<Conversation?> getConversation(String id) async {
    final snap = await _conversations.doc(id).get();
    return snap.exists ? Conversation.fromMap(snap.id, snap.data()!) : null;
  }

  /// Returns the one-to-one chat between two users, creating it if needed.
  Future<Conversation> openDirectChat({
    required String myUid,
    required String otherUid,
  }) async {
    final id = directChatId(myUid, otherUid);
    final existing = await getConversation(id);
    if (existing != null) return existing;
    final now = _now();
    final conversation = Conversation(
      id: id,
      type: ConversationType.direct,
      memberIds: {myUid, otherUid}.toList(),
      createdBy: myUid,
      createdAt: now,
      updatedAt: now,
    );
    await _conversations.doc(id).set(conversation.toMap());
    return conversation;
  }

  Future<Conversation> createGroup({
    required String creatorUid,
    required String creatorName,
    required String name,
    required List<String> memberIds,
  }) async {
    final groupName = name.trim();
    if (groupName.isEmpty) throw ArgumentError('Group name is required');
    final members = {creatorUid, ...memberIds}.toList();
    if (members.length < 2) throw ArgumentError('Add at least one member');
    final ref = _conversations.doc();
    final now = _now();
    final created = Message(
      id: messagesOf(ref.id).doc().id,
      conversationId: ref.id,
      kind: MessageKind.system,
      sentAt: now,
      senderId: creatorUid,
      senderName: creatorName,
      text: '$creatorName created the group',
    );
    final conversation = Conversation(
      id: ref.id,
      type: ConversationType.group,
      name: groupName,
      memberIds: members,
      adminIds: [creatorUid],
      createdBy: creatorUid,
      createdAt: now,
      updatedAt: now,
      lastMessage: LastMessage.of(created),
      lastReadAt: {creatorUid: now},
    );
    // The conversation must exist before rules can authorize the message.
    await ref.set(conversation.toMap());
    await messagesOf(ref.id).doc(created.id).set(created.toMap());
    return conversation;
  }

  Future<void> renameGroup(String conversationId, String name) {
    final groupName = name.trim();
    if (groupName.isEmpty) throw ArgumentError('Group name is required');
    return _conversations.doc(conversationId).update({'name': groupName});
  }

  Future<void> addMembers(String conversationId, List<String> uids) {
    if (uids.isEmpty) return Future.value();
    return _conversations
        .doc(conversationId)
        .update({'memberIds': FieldValue.arrayUnion(uids)});
  }

  Future<void> removeMember(String conversationId, String uid) {
    return _conversations.doc(conversationId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'adminIds': FieldValue.arrayRemove([uid]),
    });
  }

  /// Leaves a group. If the last admin leaves, the next member becomes admin.
  Future<void> leaveGroup(String conversationId, String uid) async {
    final conversation = await getConversation(conversationId);
    if (conversation == null) return;
    final remaining = conversation.memberIds.where((m) => m != uid).toList();
    final admins = conversation.adminIds.where((m) => m != uid).toList();
    if (admins.isEmpty && remaining.isNotEmpty && conversation.isAdmin(uid)) {
      admins.add(remaining.first);
    }
    await _conversations.doc(conversationId).update({
      'memberIds': remaining,
      'adminIds': admins,
    });
  }

  Future<void> markRead(String conversationId, String uid) {
    return _conversations
        .doc(conversationId)
        .update({'lastReadAt.$uid': writeDate(_now())});
  }

  // Messages

  /// Newest-first page of messages. Increase [limit] to load older history.
  Stream<List<Message>> watchMessages(String conversationId, {int limit = 40}) {
    return messagesOf(conversationId)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Message.fromMap(
                  d.id,
                  d.data(),
                  conversationId: conversationId,
                ))
            .toList());
  }

  /// Reserves an id so attachments can be uploaded before the message exists.
  String newMessageId(String conversationId) =>
      messagesOf(conversationId).doc().id;

  /// Sends a live message from an Orbit user and bumps the conversation.
  ///
  /// Firestore queues the write while offline; the returned future completes
  /// when the server acknowledges it, so UI code should not block on it.
  Future<Message> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    MessageKind kind = MessageKind.text,
    String text = '',
    List<Attachment> attachments = const [],
    String? messageId,
  }) async {
    final body = text.trim();
    if (kind == MessageKind.text && body.isEmpty) {
      throw ArgumentError('Message is empty');
    }
    if (kind != MessageKind.text &&
        kind != MessageKind.system &&
        attachments.isEmpty) {
      throw ArgumentError('Attachment is missing');
    }
    final ref = messagesOf(conversationId).doc(messageId);
    final message = Message(
      id: ref.id,
      conversationId: conversationId,
      kind: kind,
      sentAt: _now(),
      senderId: senderId,
      senderName: senderName,
      text: body,
      attachments: attachments,
    );
    final batch = _db.batch()
      ..set(ref, {
        ...message.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(_conversations.doc(conversationId), {
        'lastMessage': LastMessage.of(message).toMap(),
        'updatedAt': writeDate(message.sentAt),
        'lastReadAt.$senderId': writeDate(message.sentAt),
      });
    await batch.commit();
    return message;
  }

  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) throw ArgumentError('Message is empty');
    await messagesOf(conversationId).doc(messageId).update({
      'text': body,
      'editedAt': writeDate(_now()),
    });
    await _refreshPreviewIfLatest(conversationId, messageId);
  }

  /// Replaces the message with a tombstone visible to everyone.
  Future<void> deleteForEveryone({
    required String conversationId,
    required String messageId,
  }) async {
    await messagesOf(conversationId).doc(messageId).update({
      'deleted': true,
      'deletedAt': writeDate(_now()),
      'text': '',
      'attachments': <Object>[],
      'reactions': FieldValue.delete(),
    });
    await _refreshPreviewIfLatest(conversationId, messageId);
  }

  /// Sets [emoji] as [uid]'s reaction, or clears it when [emoji] is `null`.
  Future<void> setReaction({
    required String conversationId,
    required String messageId,
    required String uid,
    String? emoji,
  }) {
    return messagesOf(conversationId).doc(messageId).update({
      'reactions.$uid': emoji ?? FieldValue.delete(),
    });
  }

  /// Picking the same emoji again removes it.
  Future<void> toggleReaction(Message message, String uid, String emoji) {
    final current = message.reactions[uid];
    return setReaction(
      conversationId: message.conversationId,
      messageId: message.id,
      uid: uid,
      emoji: current == emoji ? null : emoji,
    );
  }

  Future<void> _refreshPreviewIfLatest(
    String conversationId,
    String messageId,
  ) async {
    try {
      final conversation = await getConversation(conversationId);
      if (conversation?.lastMessage?.messageId != messageId) return;
      final snap = await messagesOf(conversationId).doc(messageId).get();
      if (!snap.exists) return;
      final message = Message.fromMap(
        snap.id,
        snap.data()!,
        conversationId: conversationId,
      );
      await _conversations
          .doc(conversationId)
          .update({'lastMessage': LastMessage.of(message).toMap()});
    } catch (_) {
      // The inbox preview is cosmetic; the message itself is already updated.
    }
  }

  // Import

  /// Creates (or returns) a conversation for imported history.
  ///
  /// [externalKey] identifies the thread in the source app, e.g. a Google
  /// Messages thread id or iMessage chat GUID. [participants] lists people
  /// from the source who may not be Orbit users. [extraMemberIds] adds Orbit
  /// users who should also see the history.
  Future<Conversation> upsertImportedConversation({
    required String importerUid,
    required String source,
    required String externalKey,
    ConversationType type = ConversationType.direct,
    String name = '',
    List<Participant> participants = const [],
    List<String> extraMemberIds = const [],
  }) async {
    final id = importedConversationId(
      importerUid: importerUid,
      source: source,
      externalKey: externalKey,
    );
    final existing = await getConversation(id);
    if (existing != null) {
      return _mergeImportedThread(existing, name: name, participants: participants);
    }
    final now = _now();
    final conversation = Conversation(
      id: id,
      type: type,
      name: name.trim(),
      memberIds: {importerUid, ...extraMemberIds}.toList(),
      adminIds: [importerUid],
      createdBy: importerUid,
      createdAt: now,
      updatedAt: now,
      externalParticipants: participants,
      importSource: source,
      importKey: externalKey,
    );
    await _conversations.doc(id).set(conversation.toMap());
    return conversation;
  }

  /// Adds participants not seen before (by address) and fills in missing
  /// display names; adopts a new non-empty [name].
  Future<Conversation> _mergeImportedThread(
    Conversation existing, {
    required String name,
    required List<Participant> participants,
  }) async {
    final byAddress = {
      for (final p in existing.externalParticipants) p.address: p,
    };
    var changed = false;
    for (final p in participants) {
      final current = byAddress[p.address];
      if (current == null ||
          (current.displayName.isEmpty && p.displayName.isNotEmpty) ||
          (current.uid == null && p.uid != null)) {
        byAddress[p.address] = p;
        changed = true;
      }
    }
    final newName = name.trim();
    final rename = newName.isNotEmpty && newName != existing.name;
    if (!changed && !rename) return existing;
    final merged = byAddress.values.toList();
    await _conversations.doc(existing.id).update({
      if (changed) 'externalParticipants': merged.map((p) => p.toMap()).toList(),
      if (rename) 'name': newName,
    });
    return Conversation.fromMap(existing.id, {
      ...existing.toMap(),
      'externalParticipants': merged.map((p) => p.toMap()).toList(),
      if (rename) 'name': newName,
    });
  }

  /// Writes historical messages with their original timestamps and senders.
  ///
  /// Each message must have an [Message.importKey] (stable id from the source)
  /// so re-imports are idempotent. [Message.senderId] must be [importerUid]
  /// (messages the importer sent) or `null` with [Message.senderAddress] set
  /// (anyone else). The conversation is marked read up to the newest imported
  /// message, so history never shows up as new or unread.
  ///
  /// With [skipExisting] (the default) keys already stored are left untouched
  /// and counted in [ImportResult.skipped]; otherwise they are overwritten.
  Future<ImportResult> importMessages({
    required String conversationId,
    required String importerUid,
    required String source,
    required List<Message> messages,
    bool skipExisting = true,
  }) async {
    if (messages.isEmpty) return const ImportResult(written: 0);
    Message? newest;
    final prepared = <(DocumentReference<Map<String, dynamic>>, Message)>[];
    for (final m in messages) {
      final key = m.importKey;
      if (key == null || key.isEmpty) {
        throw ArgumentError('Imported messages need an importKey');
      }
      if (m.senderId != null && m.senderId != importerUid) {
        throw ArgumentError(
          'Imported messages can only be attributed to the importer; '
          'use senderAddress for other people',
        );
      }
      final id = importedMessageId(source: source, importKey: key);
      final message = Message(
        id: id,
        conversationId: conversationId,
        kind: m.kind,
        sentAt: m.sentAt,
        senderId: m.senderId,
        senderAddress: m.senderAddress,
        senderName: m.senderName,
        text: m.text,
        attachments: m.attachments,
        editedAt: m.editedAt,
        deleted: m.deleted,
        deletedAt: m.deletedAt,
        reactions: m.reactions,
        imported: true,
        importedBy: importerUid,
        importSource: source,
        importKey: key,
      );
      prepared.add((messagesOf(conversationId).doc(id), message));
    }

    var skipped = 0;
    if (skipExisting) {
      final existing = await existingMessageIds(
        conversationId,
        prepared.map((p) => p.$1.id).toList(),
      );
      final before = prepared.length;
      prepared.removeWhere((p) => existing.contains(p.$1.id));
      skipped = before - prepared.length;
    }
    // Duplicate keys within one call collapse to a single document.
    final unique = <String, (DocumentReference<Map<String, dynamic>>, Message)>{
      for (final p in prepared) p.$1.id: p,
    };
    skipped += prepared.length - unique.length;
    prepared
      ..clear()
      ..addAll(unique.values);
    for (final (_, message) in prepared) {
      if (newest == null || message.sentAt.isAfter(newest.sentAt)) {
        newest = message;
      }
    }
    if (prepared.isEmpty) return ImportResult(written: 0, skipped: skipped);

    for (var i = 0; i < prepared.length; i += batchSize) {
      final batch = _db.batch();
      for (final (ref, message) in prepared.skip(i).take(batchSize)) {
        batch.set(ref, message.toMap());
      }
      await batch.commit();
    }

    final conversation = await getConversation(conversationId);
    final last = conversation?.lastMessage;
    final summary = <String, Object?>{
      'lastReadAt.$importerUid': writeDate(_maxDate(
        conversation?.lastReadAt[importerUid],
        newest!.sentAt,
      )),
    };
    if (last == null || !newest.sentAt.isBefore(last.sentAt)) {
      summary['lastMessage'] = LastMessage.of(newest).toMap();
      summary['updatedAt'] = writeDate(newest.sentAt);
    }
    await _conversations.doc(conversationId).update(summary);
    return ImportResult(
      written: prepared.length,
      skipped: skipped,
      newest: newest,
    );
  }

  /// Sets or clears reactions on imported messages, keyed by message id then
  /// reactor key (`null` emoji removes it). Missing or deleted messages are
  /// skipped. Returns how many reactions actually changed.
  Future<int> applyImportedReactions({
    required String conversationId,
    required Map<String, Map<String, String?>> byMessageId,
  }) async {
    if (byMessageId.isEmpty) return 0;
    final ids = byMessageId.keys.toList();
    final current = <String, Map<String, String>>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      final snap = await messagesOf(conversationId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        final m = Message.fromMap(d.id, d.data(), conversationId: conversationId);
        if (!m.deleted) current[d.id] = m.reactions;
      }
    }
    var changed = 0;
    var batch = _db.batch();
    var pending = 0;
    for (final MapEntry(key: id, value: wanted) in byMessageId.entries) {
      final existing = current[id];
      if (existing == null) continue;
      for (final MapEntry(key: reactor, value: emoji) in wanted.entries) {
        if (existing[reactor] == emoji) continue;
        batch.update(messagesOf(conversationId).doc(id), {
          FieldPath(['reactions', reactor]): emoji ?? FieldValue.delete(),
        });
        changed++;
        if (++pending == batchSize) {
          await batch.commit();
          batch = _db.batch();
          pending = 0;
        }
      }
    }
    if (pending > 0) await batch.commit();
    return changed;
  }

  /// Which of [ids] already exist in the conversation.
  /// Firestore `whereIn` accepts at most 30 values per query.
  Future<Set<String>> existingMessageIds(
    String conversationId,
    List<String> ids,
  ) async {
    final found = <String>{};
    final unique = ids.toSet().toList();
    for (var i = 0; i < unique.length; i += 30) {
      final chunk = unique.sublist(i, (i + 30).clamp(0, unique.length));
      final snap = await messagesOf(conversationId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      found.addAll(snap.docs.map((d) => d.id));
    }
    return found;
  }

  static DateTime _maxDate(DateTime? a, DateTime b) =>
      a != null && a.isAfter(b) ? a : b;
}
