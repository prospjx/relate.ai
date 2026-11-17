import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/models.dart';

/// Uploads avatars and chat files to Firebase Storage.
///
/// Paths match `storage.rules`:
/// - `avatars/{uid}/{file}`
/// - `chats/{conversationId}/{uploaderUid}/{file}`
class MediaRepository {
  MediaRepository(this._storage);

  static const maxUploadBytes = 50 * 1024 * 1024;
  static const maxAvatarBytes = 5 * 1024 * 1024;

  final FirebaseStorage _storage;

  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (bytes.length > maxAvatarBytes) {
      throw ArgumentError('Profile pictures must be under 5 MB');
    }
    final ext = mimeType.split('/').last.replaceAll('jpeg', 'jpg');
    final ref = _storage
        .ref('avatars/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: mimeType));
    return ref.getDownloadURL();
  }

  Future<Attachment> uploadChatFile({
    required String conversationId,
    required String uploaderUid,
    required AttachmentKind kind,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    int? width,
    int? height,
    int? durationMs,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.length > maxUploadBytes) {
      throw ArgumentError('Files must be under 50 MB');
    }
    final path = chatFilePath(
      conversationId: conversationId,
      uploaderUid: uploaderUid,
      fileName: fileName,
    );
    final ref = _storage.ref(path);
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: mimeType,
        customMetadata: {'originalName': fileName},
      ),
    );
    if (onProgress != null) {
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
      }, onError: (_) {});
    }
    await task;
    return Attachment(
      kind: kind,
      url: await ref.getDownloadURL(),
      storagePath: path,
      name: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      width: width,
      height: height,
      durationMs: durationMs,
    );
  }

  /// Best-effort removal of uploaded files, e.g. after delete for everyone.
  Future<void> deleteAttachments(List<Attachment> attachments) async {
    for (final a in attachments) {
      final path = a.storagePath;
      if (path == null) continue;
      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // The message tombstone is what matters; orphaned files are harmless.
      }
    }
  }

  static String chatFilePath({
    required String conversationId,
    required String uploaderUid,
    required String fileName,
  }) {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'chats/$conversationId/$uploaderUid/${stamp}_$safe';
  }
}
