import 'dart:convert';
import 'dart:typed_data';

/// Reads top-level string / date / bool values from an XML property list.
/// iPhone backups' Info.plist is XML; Manifest.plist may be binary
/// ("bplist00"), in which case this returns an empty map and callers fall
/// back to other checks.
Map<String, Object> readXmlPlistTopLevel(Uint8List bytes) {
  if (bytes.length >= 8 && ascii.decode(bytes.sublist(0, 6), allowInvalid: true) == 'bplist') {
    return const {};
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  final result = <String, Object>{};
  final dictStart = text.indexOf('<dict>');
  if (dictStart < 0) return result;
  final re = RegExp(
    r'<key>([^<]*)</key>\s*(?:<(string|date|integer)>([^<]*)</\2>|<(true|false)\s*/>|<(dict|array|data)>)',
  );
  var depth = 0;
  var cursor = dictStart + 6;
  for (final m in re.allMatches(text, cursor)) {
    // Track nesting so keys inside nested dicts/arrays are ignored.
    final between = text.substring(cursor, m.start);
    depth += RegExp(r'<(dict|array)>').allMatches(between).length;
    depth -= RegExp(r'</(dict|array)>').allMatches(between).length;
    cursor = m.end;
    if (depth > 0) {
      if (m.group(5) != null) depth++;
      continue;
    }
    final key = _unescape(m.group(1)!);
    if (m.group(2) != null) {
      final raw = _unescape(m.group(3)!);
      switch (m.group(2)) {
        case 'date':
          final dt = DateTime.tryParse(raw);
          if (dt != null) result[key] = dt;
        case 'integer':
          final i = int.tryParse(raw);
          if (i != null) result[key] = i;
        default:
          result[key] = raw;
      }
    } else if (m.group(4) != null) {
      result[key] = m.group(4) == 'true';
    } else if (m.group(5) != null) {
      depth++;
    }
  }
  return result;
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
