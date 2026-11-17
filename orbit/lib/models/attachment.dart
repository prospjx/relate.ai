enum AttachmentKind { image, video, audio, document, gif, sticker }

/// A file or built-in asset attached to a message.
///
/// Uploaded files carry [url] (download URL) and [storagePath]. GIFs from a
/// search provider carry only [url]. Stickers carry only [stickerId], which
/// resolves against the built-in sticker pack.
class Attachment {
  const Attachment({
    required this.kind,
    this.url,
    this.storagePath,
    this.name,
    this.mimeType,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.stickerId,
  });

  final AttachmentKind kind;
  final String? url;
  final String? storagePath;
  final String? name;
  final String? mimeType;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? stickerId;

  Map<String, Object?> toMap() => {
        'kind': kind.name,
        if (url != null) 'url': url,
        if (storagePath != null) 'storagePath': storagePath,
        if (name != null) 'name': name,
        if (mimeType != null) 'mimeType': mimeType,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'durationMs': durationMs,
        if (stickerId != null) 'stickerId': stickerId,
      };

  factory Attachment.fromMap(Map<String, Object?> map) {
    final kindName = map['kind'];
    return Attachment(
      kind: AttachmentKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => AttachmentKind.document,
      ),
      url: map['url'] as String?,
      storagePath: map['storagePath'] as String?,
      name: map['name'] as String?,
      mimeType: map['mimeType'] as String?,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationMs: (map['durationMs'] as num?)?.toInt(),
      stickerId: map['stickerId'] as String?,
    );
  }
}
