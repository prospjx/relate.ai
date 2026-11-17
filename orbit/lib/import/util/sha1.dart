import 'dart:convert';
import 'dart:typed_data';

/// Minimal SHA-1 (FIPS 180-4). Used for iPhone backup file IDs
/// (`sha1("<domain>-<relativePath>")`) and stable dedupe keys, so the app
/// does not need `package:crypto`. Not used for anything security-relevant.
Uint8List sha1Bytes(List<int> message) {
  final ml = message.length;
  final paddedLength = ((ml + 9 + 63) ~/ 64) * 64;
  final data = Uint8List(paddedLength)..setRange(0, ml, message);
  data[ml] = 0x80;
  final bitLength = ml * 8;
  final bd = ByteData.sublistView(data);
  bd.setUint32(paddedLength - 8, (bitLength ~/ 0x100000000) & 0xffffffff);
  bd.setUint32(paddedLength - 4, bitLength & 0xffffffff);

  var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
  final w = Uint32List(80);
  int rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xffffffff;

  for (var chunk = 0; chunk < paddedLength; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(chunk + i * 4);
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (rotl(a, 5) + (f & 0xffffffff) + e + k + w[i]) & 0xffffffff;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
  }

  final out = ByteData(20)
    ..setUint32(0, h0)
    ..setUint32(4, h1)
    ..setUint32(8, h2)
    ..setUint32(12, h3)
    ..setUint32(16, h4);
  return out.buffer.asUint8List();
}

String sha1Hex(String input) {
  final bytes = sha1Bytes(utf8.encode(input));
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// iPhone backup file ID for a domain + relative path.
String iosBackupFileId(String domain, String relativePath) => sha1Hex('$domain-$relativePath');
