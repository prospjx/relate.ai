import 'dart:convert';
import 'dart:typed_data';

/// Best-effort extraction of the plain text from a Messages `attributedBody`
/// blob (an NSArchiver "typedstream" of an NSAttributedString). Newer macOS /
/// iOS versions often leave `message.text` NULL and only fill this column.
///
/// Layout of the part we need:
///   `... "NSString" 0x01 0x94 0x84 0x01 '+' [length] [utf-8 bytes] ...`
/// where `[length]` is a typedstream integer: one signed byte, or 0x81
/// followed by a little-endian int16, or 0x82 followed by a little-endian
/// int32. We locate the first NSString / NSMutableString class name, find
/// the following '+' (C-string type marker) and decode the string after it.
/// Returns null when nothing plausible is found.
String? extractAttributedBodyText(Uint8List? blob) {
  if (blob == null || blob.isEmpty) return null;
  for (final marker in const ['NSString', 'NSMutableString']) {
    final idx = _indexOf(blob, ascii.encode(marker));
    if (idx < 0) continue;
    final text = _readAfterMarker(blob, idx + marker.length);
    if (text != null) return text;
  }
  return null;
}

String? _readAfterMarker(Uint8List b, int start) {
  final limit = (start + 16).clamp(0, b.length);
  var i = start;
  while (i < limit && b[i] != 0x2B) {
    i++;
  }
  if (i >= limit) return null;
  i++; // skip '+'
  if (i >= b.length) return null;

  int length;
  final tag = b[i];
  if (tag == 0x81) {
    if (i + 3 > b.length) return null;
    length = b[i + 1] | (b[i + 2] << 8);
    i += 3;
  } else if (tag == 0x82) {
    if (i + 5 > b.length) return null;
    length = ByteData.sublistView(b, i + 1, i + 5).getInt32(0, Endian.little);
    i += 5;
  } else if (tag < 0x80) {
    length = tag;
    i += 1;
  } else {
    return null;
  }
  if (length <= 0 || i + length > b.length) return null;
  return utf8.decode(b.sublist(i, i + length), allowMalformed: true);
}

int _indexOf(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
