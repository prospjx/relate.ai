import 'dart:io';

import 'package:path/path.dart' as p;

const _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  'caf': 'audio/x-caf',
  'amr': 'audio/amr',
  'm4a': 'audio/mp4',
  'mp3': 'audio/mpeg',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'pdf': 'application/pdf',
  'vcf': 'text/vcard',
  'txt': 'text/plain',
};

const _extensionByMime = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/webp': 'webp',
  'video/mp4': 'mp4',
  'video/3gpp': '3gp',
  'video/quicktime': 'mov',
  'audio/amr': 'amr',
  'audio/mp4': 'm4a',
  'audio/mpeg': 'mp3',
  'text/x-vcard': 'vcf',
  'text/vcard': 'vcf',
};

String guessMimeType(String fileName) {
  final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
  return _mimeByExtension[ext] ?? 'application/octet-stream';
}

/// File-system-safe name; adds an extension derived from [mimeType] when the
/// name has none.
String safeFileName(String? name, String mimeType, {String fallback = 'attachment'}) {
  var base = (name == null || name.trim().isEmpty) ? fallback : p.basename(name.trim());
  base = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  if (base.length > 120) base = base.substring(base.length - 120);
  if (p.extension(base).isEmpty) {
    final ext = _extensionByMime[mimeType.toLowerCase()];
    if (ext != null) base = '$base.$ext';
  }
  return base;
}

/// Copies [source] to [target] unless an identical-size file already exists
/// (re-imports reuse earlier copies). Returns the target path.
Future<String> copyIfChanged(File source, String target) async {
  final t = File(target);
  if (await t.exists() && await t.length() == await source.length()) return target;
  await t.parent.create(recursive: true);
  await source.copy(target);
  return target;
}
