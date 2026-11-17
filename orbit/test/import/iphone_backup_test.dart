import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/import/import.dart';
import 'package:path/path.dart' as p;

import 'fixtures/builders.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('orbit_backup_test_'));
  tearDown(() async => tmp.delete(recursive: true));

  test('default backup folders follow Apple documentation', () {
    expect(
      IPhoneBackupLocator.defaultRoots(
        environment: {'USERPROFILE': r'C:\Users\test', 'APPDATA': r'C:\Users\test\AppData\Roaming'},
        os: 'windows',
      ),
      [r'C:\Users\test\Apple\MobileSync\Backup', r'C:\Users\test\AppData\Roaming\Apple Computer\MobileSync\Backup'],
    );
    expect(
      IPhoneBackupLocator.defaultRoots(environment: {'HOME': '/Users/test'}, os: 'macos'),
      ['/Users/test/Library/Application Support/MobileSync/Backup'],
    );
  });

  test('finds and describes backups', () async {
    final backupPath = await buildIPhoneBackup(tmp);
    await Directory(p.join(tmp.path, 'not-a-backup')).create();
    final found = await IPhoneBackupLocator.findBackups(roots: [tmp.path, p.join(tmp.path, 'missing')]);
    expect(found, hasLength(1));
    final info = found.single;
    expect(info.path, backupPath);
    expect(info.deviceName, 'Test iPhone');
    expect(info.productVersion, '17.4');
    expect(info.lastBackupDate, DateTime.utc(2024, 3, 1, 12));
    expect(info.isEncrypted, isFalse);
    expect(info.hasManifestDb, isTrue);
    expect(info.label, 'Test iPhone (iOS 17.4)');
  });

  test('imports sms.db and attachments from an unencrypted backup', () async {
    final backupPath = await buildIPhoneBackup(tmp);
    final sink = InMemoryImportSink();
    final source = IPhoneBackupSource(backupPath);
    final out = p.join(tmp.path, 'out');
    final summary = await ImportEngine().run(source, sink, options: ReadOptions(attachmentDirectory: out));
    await source.dispose();

    expect(summary.fatalError, isNull);
    expect(summary.messagesAdded, 8);
    expect(sink.threads, hasLength(3));
    final photo = sink.messagesByThread['imsg-group:chat900000000000000001']![1].attachments.single;
    expect(photo.isAvailable, isTrue);
    expect(photo.fileName, 'photo.png');
    expect(p.isWithin(out, photo.localPath!), isTrue);
    expect(File(photo.localPath!).lengthSync(), greaterThan(60));
  });

  test('resolves files through Manifest.db and by computed hash', () async {
    final backup = await IPhoneBackup.open(await buildIPhoneBackup(tmp));
    try {
      final sms = await backup.fileFor('HomeDomain', 'Library/SMS/sms.db');
      expect(p.basename(sms!.path), '3d0d7e5fb2ce288813306e4d4636395e047a3d28');
      expect(await backup.fileFor('HomeDomain', 'Library/SMS/missing.db'), isNull);
      final located = await BackupAttachmentLocator(backup)
          .locate('/var/mobile/Library/SMS/Attachments/ab/01/ATT-1/photo.png');
      expect(located, isNotNull);
    } finally {
      await backup.close();
    }
  });

  test('encrypted backups (flag in Manifest.plist) are rejected with instructions', () async {
    final path = await buildIPhoneBackup(tmp, encrypted: true);
    final summary = await ImportEngine().run(IPhoneBackupSource(path), InMemoryImportSink());
    expect(summary.fatalError, contains('encrypted'));
    expect(summary.fatalError, contains('Encrypt local backup'));
  });

  test('encrypted backups are detected from an unreadable Manifest.db too', () async {
    final path = await buildIPhoneBackup(tmp, corruptManifest: true);
    await expectLater(IPhoneBackup.open(path), throwsA(isA<ImportException>().having((e) => e.message, 'message', contains('encrypted'))));
  });

  test('a folder that is not a backup gives a clear error', () async {
    final summary = await ImportEngine().run(IPhoneBackupSource(tmp.path), InMemoryImportSink());
    expect(summary.fatalError, contains('not an iPhone backup'));
  });
}
