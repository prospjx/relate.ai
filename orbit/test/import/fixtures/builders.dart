// Synthetic fixtures for import tests. All names, numbers and messages are
// made up.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:orbit/import/util/apple_time.dart';
import 'package:orbit/import/util/sha1.dart';
import 'package:orbit/import/util/sqlite.dart';
import 'package:path/path.dart' as p;

const anaPhone = '+15551230001';
const alexEmail = 'alex@example.com';
const bankShortPhone = '+15551230003';

final t0 = DateTime.utc(2023, 1, 1, 10);

/// 1x1 transparent PNG.
const tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

String fixturePath(String name) => p.join('test', 'import', 'fixtures', name);

/// An NSAttributedString typedstream as written by Messages, wrapping [text].
Uint8List craftAttributedBody(String text) {
  final b = BytesBuilder();
  b.add([0x04, 0x0B]);
  b.add(ascii.encode('streamtyped'));
  b.add([0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12]);
  b.add(ascii.encode('NSAttributedString'));
  b.add([0x00, 0x84, 0x84, 0x08]);
  b.add(ascii.encode('NSObject'));
  b.add([0x00, 0x85, 0x92, 0x84, 0x84, 0x84, 0x08]);
  b.add(ascii.encode('NSString'));
  b.add([0x01, 0x94, 0x84, 0x01, 0x2B]);
  final utf = utf8.encode(text);
  if (utf.length < 0x80) {
    b.addByte(utf.length);
  } else {
    b.add([0x81, utf.length & 0xFF, (utf.length >> 8) & 0xFF]);
  }
  b.add(utf);
  b.add([0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x05, 0x92, 0x84, 0x84, 0x84, 0x0C]);
  b.add(ascii.encode('NSDictionary'));
  b.add([0x00, 0x86, 0x86]);
  return b.toBytes();
}

/// Builds a Messages database with the columns the importer reads (subset of
/// the real macOS chat.db / iOS sms.db schema).
///
/// Content:
/// * chat 1: iMessage 1:1 with Ana - text, attributedBody-only reply (date
///   stored in legacy seconds), a 👍 tapback, an empty (unsent) row.
/// * chat 2: group "Trip Planning" with Ana + Alex - text, photo, rename event.
/// * chat 3: SMS 1:1 with the bank number; plus one orphan message from the
///   same number not joined to any chat.
void buildChatDb(String path, {required String attachmentPathPrefix}) {
  final db = SqliteDb.open(path, create: true);
  try {
    db.execute('''
      CREATE TABLE handle (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL, service TEXT);
      CREATE TABLE chat (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT, style INTEGER,
        chat_identifier TEXT, service_name TEXT, display_name TEXT);
      CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
      CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT, text TEXT,
        attributedBody BLOB, handle_id INTEGER DEFAULT 0, service TEXT, subject TEXT,
        date INTEGER, date_read INTEGER DEFAULT 0, is_from_me INTEGER DEFAULT 0,
        is_read INTEGER DEFAULT 0, item_type INTEGER DEFAULT 0, group_title TEXT,
        associated_message_guid TEXT, associated_message_type INTEGER DEFAULT 0,
        associated_message_emoji TEXT, cache_has_attachments INTEGER DEFAULT 0);
      CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER, message_date INTEGER);
      CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT, filename TEXT,
        mime_type TEXT, transfer_name TEXT, total_bytes INTEGER, uti TEXT);
      CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
    ''');
    for (final h in [
      [anaPhone, 'iMessage'],
      [alexEmail, 'iMessage'],
      [bankShortPhone, 'SMS'],
    ]) {
      db.execute('INSERT INTO handle (id, service) VALUES (?, ?)', h);
    }
    db.execute("INSERT INTO chat (guid, style, chat_identifier, service_name, display_name) "
        "VALUES ('iMessage;-;$anaPhone', 45, '$anaPhone', 'iMessage', '')");
    db.execute("INSERT INTO chat (guid, style, chat_identifier, service_name, display_name) "
        "VALUES ('iMessage;+;chat900000000000000001', 43, 'chat900000000000000001', 'iMessage', 'Trip Planning')");
    db.execute("INSERT INTO chat (guid, style, chat_identifier, service_name, display_name) "
        "VALUES ('SMS;-;$bankShortPhone', 45, '$bankShortPhone', 'SMS', NULL)");
    for (final j in [
      [1, 1],
      [2, 1],
      [2, 2],
      [3, 3],
    ]) {
      db.execute('INSERT INTO chat_handle_join VALUES (?, ?)', j);
    }

    int ns(Duration d) => dateTimeToAppleNanoseconds(t0.add(d));
    var nextId = 0;
    int msg(int? chat, Map<String, Object?> cols) {
      final keys = cols.keys.toList();
      db.execute(
        'INSERT INTO message (${keys.join(',')}) VALUES (${List.filled(keys.length, '?').join(',')})',
        cols.values.toList(),
      );
      nextId++;
      if (chat != null) db.execute('INSERT INTO chat_message_join VALUES (?, ?, 0)', [chat, nextId]);
      return nextId;
    }

    msg(1, {
      'guid': 'GUID-M1',
      'text': 'Hello from Ana',
      'handle_id': 1,
      'service': 'iMessage',
      'date': ns(Duration.zero),
      'date_read': ns(const Duration(minutes: 1)),
      'is_read': 1,
    });
    msg(1, {
      'guid': 'GUID-M2',
      'text': null,
      'attributedBody': craftAttributedBody('Reply stored only in attributedBody ✅'),
      'handle_id': 1,
      'service': 'iMessage',
      // Legacy (pre-2017) seconds format.
      'date': ns(const Duration(minutes: 5)) ~/ 1000000000,
      'is_from_me': 1,
    });
    msg(1, {
      'guid': 'GUID-M3',
      'text': 'Liked “Hello from Ana”',
      'handle_id': 1,
      'service': 'iMessage',
      'date': ns(const Duration(minutes: 6)),
      'is_from_me': 1,
      'associated_message_guid': 'p:0/GUID-M1',
      'associated_message_type': 2001,
    });
    msg(1, {'guid': 'GUID-M9', 'handle_id': 1, 'service': 'iMessage', 'date': ns(const Duration(minutes: 7))});
    msg(2, {
      'guid': 'GUID-M4',
      'text': 'Group hi',
      'handle_id': 2,
      'service': 'iMessage',
      'date': ns(const Duration(hours: 1)),
      'is_read': 1,
    });
    final photoMessage = msg(2, {
      'guid': 'GUID-M5',
      'text': '\uFFFC',
      'handle_id': 0,
      'service': 'iMessage',
      'date': ns(const Duration(hours: 1, minutes: 2)),
      'is_from_me': 1,
      'cache_has_attachments': 1,
    });
    msg(2, {
      'guid': 'GUID-M6',
      'handle_id': 0,
      'service': 'iMessage',
      'date': ns(const Duration(hours: 1, minutes: 3)),
      'is_from_me': 1,
      'item_type': 2,
      'group_title': 'Trip Planning',
    });
    msg(3, {
      'guid': 'GUID-M7',
      'text': 'Your code is 1234',
      'handle_id': 3,
      'service': 'SMS',
      'date': ns(const Duration(days: 1)),
    });
    msg(null, {
      'guid': 'GUID-M8',
      'text': 'Orphan message',
      'handle_id': 3,
      'service': 'SMS',
      'date': ns(const Duration(days: 2)),
    });

    db.execute(
      'INSERT INTO attachment (guid, filename, mime_type, transfer_name, total_bytes, uti) VALUES (?, ?, ?, ?, ?, ?)',
      ['ATT-1', '$attachmentPathPrefix/ab/01/ATT-1/photo.png', 'image/png', 'photo.png', 70, 'public.png'],
    );
    db.execute('INSERT INTO message_attachment_join VALUES (?, 1)', [photoMessage]);
  } finally {
    db.close();
  }
}

/// A chat.db + Attachments folder laid out like ~/Library/Messages.
Future<String> buildMacMessagesFolder(Directory root) async {
  final dbPath = p.join(root.path, 'chat.db');
  buildChatDb(dbPath, attachmentPathPrefix: '~/Library/Messages/Attachments');
  final photo = File(p.join(root.path, 'Attachments', 'ab', '01', 'ATT-1', 'photo.png'));
  await photo.parent.create(recursive: true);
  await photo.writeAsBytes(base64.decode(tinyPngBase64));
  return dbPath;
}

/// An unencrypted iPhone backup folder (iOS 10+ layout) containing sms.db and
/// one attachment, indexed by Manifest.db.
Future<String> buildIPhoneBackup(Directory root, {bool encrypted = false, bool corruptManifest = false}) async {
  final dir = Directory(p.join(root.path, '00008110-000A1B2C3D4E5F60'));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'Info.plist')).writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Device Name</key>
  <string>Test iPhone</string>
  <key>Installed Applications</key>
  <array>
    <string>com.example.app</string>
  </array>
  <key>Last Backup Date</key>
  <date>2024-03-01T12:00:00Z</date>
  <key>Product Version</key>
  <string>17.4</string>
</dict>
</plist>
''');
  await File(p.join(dir.path, 'Manifest.plist')).writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>IsEncrypted</key>
  <${encrypted ? 'true' : 'false'}/>
  <key>Lockdown</key>
  <dict>
    <key>IsEncrypted</key>
    <true/>
  </dict>
</dict>
</plist>
''');

  final smsDb = File(p.join(dir.path, smsId.substring(0, 2), smsId));
  await smsDb.parent.create(recursive: true);
  buildChatDb(smsDb.path, attachmentPathPrefix: '~/Library/SMS/Attachments');

  const attachmentRelative = 'Library/SMS/Attachments/ab/01/ATT-1/photo.png';
  final attachmentId = iosBackupFileId('MediaDomain', attachmentRelative);
  final attachment = File(p.join(dir.path, attachmentId.substring(0, 2), attachmentId));
  await attachment.parent.create(recursive: true);
  await attachment.writeAsBytes(base64.decode(tinyPngBase64));

  final manifestPath = p.join(dir.path, 'Manifest.db');
  if (corruptManifest) {
    await File(manifestPath).writeAsBytes(List.generate(4096, (i) => (i * 37) & 0xFF));
  } else {
    final m = SqliteDb.open(manifestPath, create: true);
    m.execute('CREATE TABLE Files (fileID TEXT PRIMARY KEY, domain TEXT, relativePath TEXT, flags INTEGER, file BLOB)');
    m.execute('INSERT INTO Files VALUES (?, ?, ?, 1, NULL)', [smsId, 'HomeDomain', 'Library/SMS/sms.db']);
    m.execute('INSERT INTO Files VALUES (?, ?, ?, 1, NULL)', [attachmentId, 'MediaDomain', attachmentRelative]);
    m.execute('INSERT INTO Files VALUES (?, ?, ?, 2, NULL)',
        [iosBackupFileId('MediaDomain', 'Library/SMS/Attachments'), 'MediaDomain', 'Library/SMS/Attachments']);
    m.close();
  }
  return dir.path;
}

String get smsId => iosBackupFileId('HomeDomain', 'Library/SMS/sms.db');

/// Writes a single-entry deflate .zip (like SMS Backup & Restore's .xml.zip).
Future<void> writeZip(String zipPath, String entryName, List<int> content) async {
  final compressed = ZLibEncoder(raw: true).convert(content);
  final name = utf8.encode(entryName);
  final crc = _crc32(content);
  final local = BytesBuilder()
    ..add(_u32(0x04034b50))
    ..add(_u16(20))
    ..add(_u16(0))
    ..add(_u16(8))
    ..add(_u32(0))
    ..add(_u32(crc))
    ..add(_u32(compressed.length))
    ..add(_u32(content.length))
    ..add(_u16(name.length))
    ..add(_u16(0))
    ..add(name)
    ..add(compressed);
  final central = BytesBuilder()
    ..add(_u32(0x02014b50))
    ..add(_u16(20))
    ..add(_u16(20))
    ..add(_u16(0))
    ..add(_u16(8))
    ..add(_u32(0))
    ..add(_u32(crc))
    ..add(_u32(compressed.length))
    ..add(_u32(content.length))
    ..add(_u16(name.length))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(name);
  final localBytes = local.toBytes();
  final centralBytes = central.toBytes();
  final eocd = BytesBuilder()
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(1))
    ..add(_u16(1))
    ..add(_u32(centralBytes.length))
    ..add(_u32(localBytes.length))
    ..add(_u16(0));
  await File(zipPath).writeAsBytes([...localBytes, ...centralBytes, ...eocd.toBytes()]);
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
