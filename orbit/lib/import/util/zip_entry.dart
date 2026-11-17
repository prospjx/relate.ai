import 'dart:io';
import 'dart:typed_data';

import '../core.dart';

/// Streams one entry of a .zip without extracting the archive, using only
/// `dart:io` (stored or deflate entries, no Zip64, no encryption). Enough
/// for SMS Backup & Restore `.xml.zip` backups, whose XML is the first entry.
Future<Stream<List<int>>> openZipEntry(File file, {bool Function(String name)? match}) async {
  final raf = await file.open();
  try {
    final length = await raf.length();
    final tailSize = length < 65557 ? length : 65557;
    await raf.setPosition(length - tailSize);
    final tail = await raf.read(tailSize);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const ImportException('This .zip file is damaged or not a zip archive.');
    }
    final e = ByteData.sublistView(tail, eocd);
    final entries = e.getUint16(10, Endian.little);
    final cdOffset = e.getUint32(16, Endian.little);
    if (cdOffset == 0xFFFFFFFF) {
      throw const ImportException('Zip archives larger than 4 GB are not supported.',
          hint: 'Unzip the backup first and import the .xml file.');
    }

    await raf.setPosition(cdOffset);
    final cd = await raf.read((length - cdOffset).clamp(0, 1 << 26));
    var p = 0;
    for (var n = 0; n < entries; n++) {
      final h = ByteData.sublistView(cd, p);
      if (h.getUint32(0, Endian.little) != 0x02014b50) break;
      final flags = h.getUint16(8, Endian.little);
      final method = h.getUint16(10, Endian.little);
      final compressedSize = h.getUint32(20, Endian.little);
      final nameLen = h.getUint16(28, Endian.little);
      final extraLen = h.getUint16(30, Endian.little);
      final commentLen = h.getUint16(32, Endian.little);
      final localOffset = h.getUint32(42, Endian.little);
      final name = String.fromCharCodes(cd.sublist(p + 46, p + 46 + nameLen));
      p += 46 + nameLen + extraLen + commentLen;
      if (name.endsWith('/') || (match != null && !match(name))) continue;

      if (flags & 1 != 0) {
        throw const ImportException('This backup .zip is password-protected.',
            hint: 'Open it with a zip tool using your SMS Backup & Restore password, then import the .xml file inside.');
      }
      await raf.setPosition(localOffset);
      final lh = ByteData.sublistView(await raf.read(30));
      if (lh.getUint32(0, Endian.little) != 0x04034b50) {
        throw const ImportException('This .zip file is damaged.');
      }
      final dataStart = localOffset + 30 + lh.getUint16(26, Endian.little) + lh.getUint16(28, Endian.little);
      final raw = file.openRead(dataStart, dataStart + compressedSize);
      switch (method) {
        case 0:
          return raw;
        case 8:
          return raw.transform(ZLibDecoder(raw: true));
        default:
          throw ImportException('Unsupported zip compression method $method.',
              hint: 'Unzip the backup first and import the .xml file.');
      }
    }
    throw const ImportException('No matching file found inside the .zip.');
  } finally {
    await raf.close();
  }
}
