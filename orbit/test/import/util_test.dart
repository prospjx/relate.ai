import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/import/sources/iphone_backup.dart';
import 'package:orbit/import/util/address.dart';
import 'package:orbit/import/util/apple_time.dart';
import 'package:orbit/import/util/contacts.dart';
import 'package:orbit/import/util/plist.dart';
import 'package:orbit/import/util/sha1.dart';
import 'package:orbit/import/util/typedstream.dart';
import 'package:orbit/import/util/xml_pull.dart';

import 'fixtures/builders.dart';

void main() {
  group('sha1', () {
    test('matches FIPS test vectors', () {
      expect(sha1Hex(''), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(sha1Hex('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(sha1Hex('The quick brown fox jumps over the lazy dog'), '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12');
      expect(sha1Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
          '84983e441c3bd26ebaae4aa1f95129e5e54670f1');
    });

    test('sms.db file ID in iPhone backups', () {
      expect(iosBackupFileId('HomeDomain', 'Library/SMS/sms.db'), '3d0d7e5fb2ce288813306e4d4636395e047a3d28');
      expect(iosBackupFileId(smsDbDomain, smsDbRelativePath), smsDbFileId);
    });
  });

  group('Apple timestamps', () {
    test('seconds and nanoseconds since 2001 decode to the same instant', () {
      final expected = DateTime.utc(2023, 1, 1, 10);
      const seconds = 694260000; // 2023-01-01T10:00:00Z - 2001-01-01
      expect(appleTimestampToDateTime(seconds), expected);
      expect(appleTimestampToDateTime(seconds * 1000000000), expected);
      expect(appleTimestampToDateTime(dateTimeToAppleNanoseconds(expected)), expected);
    });

    test('keeps sub-second precision for nanoseconds', () {
      final dt = appleTimestampToDateTime(694260000 * 1000000000 + 123456000)!;
      expect(dt.millisecond, 123);
      expect(dt.microsecond, 456);
    });

    test('zero / null mean "never"', () {
      expect(appleTimestampToDateTime(0), isNull);
      expect(appleTimestampToDateTime(null), isNull);
    });

    test('epoch itself', () {
      expect(appleTimestampToDateTime(1), DateTime.utc(2001, 1, 1, 0, 0, 1));
    });
  });

  group('attributedBody', () {
    test('extracts short text', () {
      expect(extractAttributedBodyText(craftAttributedBody('Hello there')), 'Hello there');
    });

    test('extracts text longer than 127 bytes (0x81 length prefix) with emoji', () {
      final long = '${'Long message ' * 20}🎉 done';
      expect(utf8.encode(long).length, greaterThan(127));
      expect(extractAttributedBodyText(craftAttributedBody(long)), long);
    });

    test('handles NSMutableString blobs', () {
      final blob = craftAttributedBody('Mutable');
      final s = latin1.decode(blob).replaceFirst('NSString', 'NSMutableString');
      expect(extractAttributedBodyText(Uint8List.fromList(latin1.encode(s))), 'Mutable');
    });

    test('returns null for garbage, empty or truncated blobs', () {
      expect(extractAttributedBodyText(null), isNull);
      expect(extractAttributedBodyText(Uint8List(0)), isNull);
      expect(extractAttributedBodyText(Uint8List.fromList(List.generate(64, (i) => i))), isNull);
      final blob = craftAttributedBody('This will be cut off');
      expect(extractAttributedBodyText(Uint8List.sublistView(blob, 0, blob.length - 30)), isNull);
    });
  });

  group('addresses', () {
    test('normalizes phone formats and emails', () {
      expect(normalizeAddress('+1 (555) 123-0001'), '5551230001');
      expect(normalizeAddress('(555) 123-0001'), '5551230001');
      expect(normalizeAddress('+44 7700 900123'), normalizeAddress('07700 900123'));
      expect(normalizeAddress('Alex@Example.com '), 'alex@example.com');
      expect(normalizeAddress('12345'), '12345');
      expect(normalizeAddress('BANK'), 'bank');
    });

    test('group keys ignore order and formatting', () {
      expect(groupThreadKey(['+15551230002', '(555) 123-0001']), groupThreadKey(['5551230001', '+1 555 123 0002']));
      expect(directThreadKey('+15551230001'), directThreadKey('555-123-0001'));
    });

    test('own address detection', () {
      expect(isOwnAddress('insert-address-token', {}), isTrue);
      expect(isOwnAddress('+1 555 000 9999', {'5550009999'}), isTrue);
      expect(isOwnAddress('+15551230001', {'5550009999'}), isFalse);
    });
  });

  group('xml tokenizer', () {
    const xml = '<?xml version="1.0"?><!-- a > b "c" --><root count="2">'
        '<item a="x &gt; y" b=\'it&apos;s\' emoji="&#55357;&#56832;"/>'
        '<item a="&#x41;&#66;&amp;"></item>\n</root>';

    List<String> describe(List<XmlToken> tokens) => [
          for (final t in tokens)
            switch (t) {
              XmlStartTag(:final name, :final attributes, :final selfClosing) =>
                '<$name ${attributes.entries.map((e) => '${e.key}=${e.value}').join(' ')}${selfClosing ? '/' : ''}>',
              XmlEndTag(:final name) => '</$name>',
            },
        ];

    final expected = [
      '<root count=2>',
      '<item a=x > y b=it\'s emoji=😀/>',
      '<item a=AB&>',
      '</item>',
      '</root>',
    ];

    test('parses a whole document', () async {
      expect(describe(await xmlTokens(Stream.value(xml)).toList()), expected);
    });

    for (final size in [1, 2, 3, 7, 13]) {
      test('parses identically when split into $size-char chunks', () async {
        final chunks = [for (var i = 0; i < xml.length; i += size) xml.substring(i, (i + size).clamp(0, xml.length))];
        expect(describe(await xmlTokens(Stream.fromIterable(chunks)).toList()), expected);
      });
    }

    test('reports truncated files', () async {
      expect(xmlTokens(Stream.value('<root><item a="1')).toList(), throwsA(isA<XmlFormatException>()));
    });
  });

  group('vCard', () {
    test('parses names, phones and emails including folded lines', () {
      final book = ContactBook.parseVcf('BEGIN:VCARD\r\nVERSION:3.0\r\nN:Example;Ana;;;\r\nFN:Ana Ex\r\n ample\r\n'
          'TEL;TYPE=CELL:+1 555-123-0001\r\nEMAIL;TYPE=INTERNET:ana@example.com\r\nEND:VCARD\r\n'
          'BEGIN:VCARD\nVERSION:2.1\nN:Example;Ben\nitem1.TEL:(555) 123-0002\nEND:VCARD\n');
      expect(book.lookup('+15551230001'), 'Ana Example');
      expect(book.lookup('ANA@example.com'), 'Ana Example');
      expect(book.lookup('5551230002'), 'Ben Example');
      expect(book.lookup('5559999999'), isNull);
    });
  });

  group('plist', () {
    test('reads top-level values and ignores nested keys', () {
      final values = readXmlPlistTopLevel(Uint8List.fromList(utf8.encode('''
<plist><dict>
  <key>Lockdown</key><dict><key>Device Name</key><string>Nested</string></dict>
  <key>Device Name</key><string>Top &amp; Level</string>
  <key>IsEncrypted</key><true/>
  <key>Last Backup Date</key><date>2024-03-01T12:00:00Z</date>
</dict></plist>''')));
      expect(values['Device Name'], 'Top & Level');
      expect(values['IsEncrypted'], true);
      expect(values['Last Backup Date'], DateTime.utc(2024, 3, 1, 12));
    });

    test('binary plists are reported as unknown', () {
      expect(readXmlPlistTopLevel(Uint8List.fromList([...ascii.encode('bplist00'), 0, 1, 2])), isEmpty);
    });
  });
}
