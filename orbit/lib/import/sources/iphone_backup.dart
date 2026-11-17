import 'dart:io';

import 'package:path/path.dart' as p;

import '../core.dart';
import '../util/plist.dart';
import '../util/sha1.dart';
import '../util/sqlite.dart';
import 'imessage_db_source.dart';

const smsDbDomain = 'HomeDomain';
const smsDbRelativePath = 'Library/SMS/sms.db';

/// `sha1("HomeDomain-Library/SMS/sms.db")`, the file name of sms.db inside
/// every iPhone backup (verified by a unit test against our SHA-1).
const smsDbFileId = '3d0d7e5fb2ce288813306e4d4636395e047a3d28';

class IPhoneBackupInfo {
  IPhoneBackupInfo({
    required this.path,
    this.deviceName,
    this.productVersion,
    this.lastBackupDate,
    this.isEncrypted,
    this.hasManifestDb = false,
  });

  final String path;
  final String? deviceName;
  final String? productVersion;
  final DateTime? lastBackupDate;

  /// From Manifest.plist when readable as XML; null when unknown (binary
  /// plist) until [IPhoneBackup.open] probes Manifest.db.
  final bool? isEncrypted;
  final bool hasManifestDb;

  String get label {
    final name = deviceName ?? p.basename(path);
    final ios = productVersion == null ? '' : ' (iOS $productVersion)';
    return '$name$ios';
  }
}

class IPhoneBackupLocator {
  /// Default backup folders documented by Apple (support.apple.com/108809):
  /// Windows: %USERPROFILE%\Apple\MobileSync\Backup (Apple Devices app /
  /// Microsoft Store iTunes) and %APPDATA%\Apple Computer\MobileSync\Backup
  /// (classic iTunes). macOS: ~/Library/Application Support/MobileSync/Backup.
  static List<String> defaultRoots({Map<String, String>? environment, String? os}) {
    final env = environment ?? Platform.environment;
    final system = os ?? Platform.operatingSystem;
    if (system == 'windows') {
      return [
        if (env['USERPROFILE'] != null) p.windows.join(env['USERPROFILE']!, 'Apple', 'MobileSync', 'Backup'),
        if (env['APPDATA'] != null) p.windows.join(env['APPDATA']!, 'Apple Computer', 'MobileSync', 'Backup'),
      ];
    }
    if (system == 'macos') {
      return [
        if (env['HOME'] != null)
          p.posix.join(env['HOME']!, 'Library', 'Application Support', 'MobileSync', 'Backup'),
      ];
    }
    return const [];
  }

  /// Lists backups under [roots] (defaults to [defaultRoots]). Folders that
  /// can't be listed (missing, or blocked by macOS privacy) are skipped and
  /// reported via [onIssue].
  static Future<List<IPhoneBackupInfo>> findBackups({
    List<String>? roots,
    void Function(String message)? onIssue,
  }) async {
    final result = <IPhoneBackupInfo>[];
    for (final root in roots ?? defaultRoots()) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: true)) {
          if (entity is Directory) {
            final info = await inspect(entity.path);
            if (info != null) result.add(info);
          }
        }
      } on FileSystemException catch (e) {
        onIssue?.call(
          'Could not open $root (${e.osError?.message ?? e.message}). '
          '${Platform.isMacOS ? 'Give Orbit Full Disk Access in System Settings > Privacy & Security.' : ''}',
        );
      }
    }
    result.sort((a, b) => (b.lastBackupDate ?? DateTime(0)).compareTo(a.lastBackupDate ?? DateTime(0)));
    return result;
  }

  /// Returns info if [dir] looks like an iPhone backup folder.
  static Future<IPhoneBackupInfo?> inspect(String dir) async {
    final infoFile = File(p.join(dir, 'Info.plist'));
    final manifestDb = File(p.join(dir, 'Manifest.db'));
    final manifestPlist = File(p.join(dir, 'Manifest.plist'));
    final hasDb = await manifestDb.exists();
    if (!await infoFile.exists() && !hasDb && !await manifestPlist.exists()) return null;

    final info = await infoFile.exists() ? readXmlPlistTopLevel(await infoFile.readAsBytes()) : const <String, Object>{};
    final manifest =
        await manifestPlist.exists() ? readXmlPlistTopLevel(await manifestPlist.readAsBytes()) : const <String, Object>{};
    return IPhoneBackupInfo(
      path: dir,
      deviceName: (info['Device Name'] ?? info['Display Name']) as String?,
      productVersion: info['Product Version'] as String?,
      lastBackupDate: info['Last Backup Date'] as DateTime?,
      isEncrypted: manifest['IsEncrypted'] as bool?,
      hasManifestDb: hasDb,
    );
  }
}

/// Read-only access to an unencrypted iPhone backup.
///
/// Encrypted backups are not supported: Manifest.db and every file are
/// AES-encrypted with keys protected by the backup password (PBKDF2 with
/// millions of iterations + AES key unwrap). Implementing that safely would
/// need a crypto dependency and asking for the password; instead we detect
/// it and tell the user how to make an unencrypted backup.
class IPhoneBackup {
  IPhoneBackup._(this.path, this._manifest, this._tempDir);

  final String path;
  final SqliteDb? _manifest;
  final Directory _tempDir;

  static Future<IPhoneBackup> open(String backupDir) async {
    final info = await IPhoneBackupLocator.inspect(backupDir);
    if (info == null) {
      throw ImportException('"$backupDir" is not an iPhone backup folder.',
          hint: 'Choose the folder that contains Manifest.db and Info.plist.');
    }
    if (info.isEncrypted == true) throw _encrypted();

    final temp = await Directory.systemTemp.createTemp('orbit_backup_');
    SqliteDb? manifest;
    if (info.hasManifestDb) {
      final copy = await copySqliteForReading(p.join(backupDir, 'Manifest.db'), temp.path);
      try {
        manifest = SqliteDb.open(copy);
        manifest.select('SELECT COUNT(*) FROM Files');
      } on SqliteException {
        // An encrypted backup's Manifest.db is not valid SQLite.
        manifest?.close();
        await temp.delete(recursive: true);
        throw _encrypted();
      } on ImportException {
        await temp.delete(recursive: true);
        rethrow;
      }
    }
    return IPhoneBackup._(backupDir, manifest, temp);
  }

  static ImportException _encrypted() => const ImportException(
        'This iPhone backup is encrypted, so Orbit cannot read it.',
        hint: 'In iTunes / Apple Devices (Windows) or Finder (Mac), untick "Encrypt local backup" '
            '(you will need the backup password), click "Back Up Now", then try again.',
      );

  /// Path to the stored file for [domain]/[relativePath], or null if it is
  /// not in the backup. Uses Manifest.db, falling back to the computed
  /// SHA-1 file ID (older backups without Manifest.db).
  Future<File?> fileFor(String domain, String relativePath) async {
    final computed = iosBackupFileId(domain, relativePath);
    final candidates = <String>[computed];
    final manifest = _manifest;
    if (manifest != null) {
      final rows = manifest.select(
        'SELECT fileID FROM Files WHERE domain = ? AND relativePath = ? LIMIT 1',
        [domain, relativePath],
      );
      if (rows.isNotEmpty) candidates.insert(0, rows.first['fileID'] as String);
    }
    for (final id in candidates) {
      for (final f in [File(p.join(path, id.substring(0, 2), id)), File(p.join(path, id))]) {
        if (await f.exists()) return f;
      }
    }
    return null;
  }

  Future<File> smsDatabase() async {
    final f = await fileFor(smsDbDomain, smsDbRelativePath);
    if (f == null) {
      throw const ImportException('This backup does not contain Messages (sms.db not found).',
          hint: 'Make sure the backup finished without errors and was a full "back up to this computer" backup, then try again.');
    }
    return f;
  }

  /// Copies sms.db (plus its -wal journal if the backup has one, otherwise
  /// the newest messages would be missing) into a private folder.
  Future<String> extractSmsDatabase() async {
    final db = await smsDatabase();
    final target = p.join(_tempDir.path, 'sms.db');
    await db.copy(target);
    final wal = await fileFor(smsDbDomain, '$smsDbRelativePath-wal');
    if (wal != null) await wal.copy('$target-wal');
    return target;
  }

  Future<void> close() async {
    _manifest?.close();
    if (await _tempDir.exists()) {
      try {
        await _tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Resolves sms.db attachment paths ("~/Library/SMS/Attachments/..." or
/// "/var/mobile/Library/SMS/Attachments/...") to MediaDomain files.
class BackupAttachmentLocator implements AttachmentLocator {
  BackupAttachmentLocator(this.backup);

  final IPhoneBackup backup;

  @override
  Future<File?> locate(String dbFilename) async {
    final i = dbFilename.indexOf('Library/SMS/');
    if (i < 0) return null;
    final relative = dbFilename.substring(i);
    return await backup.fileFor('MediaDomain', relative) ?? await backup.fileFor('HomeDomain', relative);
  }
}

class IPhoneBackupSource extends ImportSource {
  IPhoneBackupSource(this.backupDir);

  final String backupDir;
  IPhoneBackup? _backup;
  IMessageDbSource? _inner;

  @override
  String get displayName => 'iPhone backup';

  @override
  Future<void> read(
    ImportVisitor visitor, {
    required ReadOptions options,
    required CancellationToken token,
    ProgressCallback? onProgress,
  }) async {
    final backup = _backup ??= await IPhoneBackup.open(backupDir);
    final inner = _inner ??= IMessageDbSource(
      dbPath: await backup.extractSmsDatabase(),
      locator: BackupAttachmentLocator(backup),
      displayName: displayName,
    );
    await inner.read(visitor, options: options, token: token, onProgress: onProgress);
  }

  @override
  Future<void> dispose() async {
    await _inner?.dispose();
    await _backup?.close();
    _inner = null;
    _backup = null;
  }
}
