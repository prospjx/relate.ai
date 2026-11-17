/// A small streaming XML tokenizer, enough for SMS Backup & Restore files:
/// start/end tags with attributes; comments, processing instructions,
/// DOCTYPE and text nodes are skipped. Works chunk-by-chunk so multi-GB
/// backups never need to be held in memory at once (only the current tag,
/// whose base64 `data` attribute can be a few MB).
library;

sealed class XmlToken {}

class XmlStartTag extends XmlToken {
  XmlStartTag(this.name, this.attributes, {required this.selfClosing});

  final String name;
  final Map<String, String> attributes;
  final bool selfClosing;
}

class XmlEndTag extends XmlToken {
  XmlEndTag(this.name);

  final String name;
}

class XmlFormatException implements Exception {
  XmlFormatException(this.message);

  final String message;

  @override
  String toString() => 'XmlFormatException: $message';
}

Stream<XmlToken> xmlTokens(Stream<String> chunks) async* {
  final tokenizer = XmlChunkTokenizer();
  await for (final chunk in chunks) {
    for (final token in tokenizer.add(chunk)) {
      yield token;
    }
  }
  tokenizer.close();
}

enum _Mode { text, tagStart, element, special }

class XmlChunkTokenizer {
  _Mode _mode = _Mode.text;
  final List<String> _parts = [];
  int _quote = 0;
  final StringBuffer _special = StringBuffer();

  static const _lt = 0x3C, _gt = 0x3E, _dq = 0x22, _sq = 0x27;

  List<XmlToken> add(String chunk) {
    final out = <XmlToken>[];
    var pos = 0;
    final len = chunk.length;
    while (pos < len) {
      switch (_mode) {
        case _Mode.text:
          final idx = chunk.indexOf('<', pos);
          if (idx < 0) return out;
          pos = idx + 1;
          _mode = _Mode.tagStart;
        case _Mode.tagStart:
          final c = chunk.codeUnitAt(pos);
          if (c == 0x21 /* ! */ || c == 0x3F /* ? */) {
            _special.clear();
            _mode = _Mode.special;
          } else {
            _parts.clear();
            _quote = 0;
            _mode = _Mode.element;
          }
        case _Mode.element:
          final start = pos;
          var i = pos;
          var found = -1;
          var q = _quote;
          while (i < len) {
            final c = chunk.codeUnitAt(i);
            if (q != 0) {
              if (c == q) q = 0;
            } else if (c == _dq || c == _sq) {
              q = c;
            } else if (c == _gt) {
              found = i;
              break;
            } else if (c == _lt) {
              throw XmlFormatException('Unexpected "<" inside a tag');
            }
            i++;
          }
          _quote = q;
          if (found < 0) {
            _parts.add(chunk.substring(start));
            return out;
          }
          _parts.add(chunk.substring(start, found));
          final raw = _parts.length == 1 ? _parts.first : _parts.join();
          _parts.clear();
          out.add(_parseTag(raw));
          pos = found + 1;
          _mode = _Mode.text;
        case _Mode.special:
          final idx = chunk.indexOf('>', pos);
          if (idx < 0) {
            _special.write(chunk.substring(pos));
            return out;
          }
          _special.write(chunk.substring(pos, idx + 1));
          pos = idx + 1;
          final s = _special.toString();
          final incomplete = (s.startsWith('!--') && !s.endsWith('-->')) ||
              (s.startsWith('![CDATA[') && !s.endsWith(']]>')) ||
              (s.startsWith('?') && !s.endsWith('?>'));
          if (!incomplete) {
            _special.clear();
            _mode = _Mode.text;
          }
      }
    }
    return out;
  }

  void close() {
    if (_mode == _Mode.element || _mode == _Mode.special) {
      throw XmlFormatException('File ended in the middle of a tag (truncated backup?)');
    }
  }

  XmlToken _parseTag(String raw) {
    if (raw.startsWith('/')) return XmlEndTag(raw.substring(1).trim());
    var body = raw;
    var selfClosing = false;
    final trimmedEnd = body.trimRight();
    if (trimmedEnd.endsWith('/')) {
      selfClosing = true;
      body = trimmedEnd.substring(0, trimmedEnd.length - 1);
    }
    var i = 0;
    final n = body.length;
    while (i < n && !_isSpace(body.codeUnitAt(i))) {
      i++;
    }
    final name = body.substring(0, i);
    final attrs = <String, String>{};
    while (i < n) {
      while (i < n && _isSpace(body.codeUnitAt(i))) {
        i++;
      }
      if (i >= n) break;
      final nameStart = i;
      while (i < n && body.codeUnitAt(i) != 0x3D /* = */ && !_isSpace(body.codeUnitAt(i))) {
        i++;
      }
      final attrName = body.substring(nameStart, i);
      while (i < n && _isSpace(body.codeUnitAt(i))) {
        i++;
      }
      if (i >= n || body.codeUnitAt(i) != 0x3D) {
        attrs[attrName] = '';
        continue;
      }
      i++;
      while (i < n && _isSpace(body.codeUnitAt(i))) {
        i++;
      }
      if (i >= n) break;
      final q = body.codeUnitAt(i);
      if (q != _dq && q != _sq) throw XmlFormatException('Unquoted attribute "$attrName" in <$name>');
      final end = body.indexOf(String.fromCharCode(q), i + 1);
      if (end < 0) throw XmlFormatException('Unterminated attribute "$attrName" in <$name>');
      attrs[attrName] = decodeXmlEntities(body.substring(i + 1, end));
      i = end + 1;
    }
    return XmlStartTag(name, attrs, selfClosing: selfClosing);
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}

/// Decodes the five predefined entities and numeric character references.
/// SMS Backup & Restore writes emoji as two numeric references to UTF-16
/// surrogates (e.g. `&#55357;&#56832;`); writing each code unit in sequence
/// recombines them into a valid Dart string.
String decodeXmlEntities(String s) {
  if (!s.contains('&')) return s;
  final sb = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final amp = s.indexOf('&', i);
    if (amp < 0) {
      sb.write(s.substring(i));
      break;
    }
    sb.write(s.substring(i, amp));
    final semi = s.indexOf(';', amp);
    if (semi < 0 || semi - amp > 12) {
      sb.write('&');
      i = amp + 1;
      continue;
    }
    final entity = s.substring(amp + 1, semi);
    switch (entity) {
      case 'amp':
        sb.write('&');
      case 'lt':
        sb.write('<');
      case 'gt':
        sb.write('>');
      case 'quot':
        sb.write('"');
      case 'apos':
        sb.write("'");
      default:
        int? code;
        if (entity.startsWith('#x') || entity.startsWith('#X')) {
          code = int.tryParse(entity.substring(2), radix: 16);
        } else if (entity.startsWith('#')) {
          code = int.tryParse(entity.substring(1));
        }
        if (code == null || code < 0 || code > 0x10FFFF) {
          sb.write('&$entity;');
        } else {
          sb.writeCharCode(code);
        }
    }
    i = semi + 1;
  }
  return sb.toString();
}
