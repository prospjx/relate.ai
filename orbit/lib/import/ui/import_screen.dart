import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../core.dart';
import '../engine.dart';
import '../models.dart';
import '../sink.dart';
import '../sources/android_device_source.dart';
import '../sources/imessage_db_source.dart';
import '../sources/iphone_backup.dart';
import '../sources/sms_backup_restore_source.dart';
import '../util/contacts.dart';

enum ImportSourceKind { iphoneBackup, macMessages, smsBackupRestore, androidDevice }

enum ImportPathKind { file, directory }

/// Picks a file or folder and returns its path (null when cancelled).
typedef ImportPathPicker = Future<String?> Function(ImportPathKind kind, {List<String>? extensions});

/// Default picker using `package:file_picker`. Users can always type or
/// paste a path instead.
Future<String?> filePickerImportPath(ImportPathKind kind, {List<String>? extensions}) async {
  if (kind == ImportPathKind.directory) {
    final uri = await FilePicker.pickDirectory();
    return uri == null || uri.scheme != 'file' ? null : uri.toFilePath();
  }
  final file = await FilePicker.pickFile(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  return file?.path;
}

/// Where recovered photos/videos go when the app doesn't pass a folder.
/// Desktop: the per-user app-data folder. Mobile: derived from the app's
/// temp folder (pass [ImportScreen.attachmentDirectory] from path_provider's
/// application support directory for a guaranteed persistent location).
String defaultImportAttachmentDirectory() {
  final env = Platform.environment;
  if (Platform.isWindows && env['APPDATA'] != null) {
    return p.join(env['APPDATA']!, 'Orbit', 'imported_attachments');
  }
  if (Platform.isMacOS && env['HOME'] != null) {
    return p.join(env['HOME']!, 'Library', 'Application Support', 'Orbit', 'imported_attachments');
  }
  if (Platform.isLinux && env['HOME'] != null) {
    return p.join(env['XDG_DATA_HOME'] ?? p.join(env['HOME']!, '.local', 'share'), 'orbit', 'imported_attachments');
  }
  final temp = Directory.systemTemp.path;
  if (Platform.isAndroid && p.basename(temp) == 'cache') {
    return p.join(p.dirname(temp), 'files', 'imported_attachments');
  }
  if (Platform.isIOS && p.basename(temp) == 'tmp') {
    return p.join(p.dirname(temp), 'Library', 'Application Support', 'imported_attachments');
  }
  return p.join(temp, 'orbit_imported_attachments');
}

/// Step-by-step import flow: choose source -> how-to + pick file -> preview
/// -> import with progress -> summary. Pops with the [ImportSummary] when
/// an import ran.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.sink,
    this.pickPath = filePickerImportPath,
    this.attachmentDirectory,
    this.androidBridge,
    this.initialSource,
  });

  final ImportSink sink;

  /// File/folder picker; pass null to only allow typed paths.
  final ImportPathPicker? pickPath;

  /// Where recovered photos/videos are saved. Defaults to
  /// [defaultImportAttachmentDirectory].
  final String? attachmentDirectory;
  final AndroidSmsBridge? androidBridge;
  final ImportSourceKind? initialSource;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

enum _Step { choose, configure, scanning, preview, importing, done }

class _ImportScreenState extends State<ImportScreen> {
  _Step _step = _Step.choose;
  ImportSourceKind? _kind;
  final _path = TextEditingController();
  final _attachmentsPath = TextEditingController();
  final _vcfPath = TextEditingController();
  final _ownNumbers = TextEditingController();
  List<IPhoneBackupInfo>? _backups;
  String? _backupSearchNote;
  String? _error;

  ImportSource? _source;
  ImportPreview? _preview;
  ImportProgress? _progress;
  ImportSummary? _summary;
  CancellationToken? _token;
  ImportEngine? _engine;
  ReadOptions? _options;

  @override
  void initState() {
    super.initState();
    if (widget.initialSource != null) _select(widget.initialSource!);
  }

  @override
  void dispose() {
    _token?.cancel();
    _source?.dispose();
    for (final c in [_path, _attachmentsPath, _vcfPath, _ownNumbers]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- flow -------------------------------------------------------------

  void _select(ImportSourceKind kind) {
    _kind = kind;
    _error = null;
    _path.clear();
    _backups = null;
    if (kind == ImportSourceKind.macMessages && !kIsWeb && Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      _path.text = p.join(home, 'Library', 'Messages', 'chat.db');
      _attachmentsPath.text = p.join(home, 'Library', 'Messages', 'Attachments');
    }
    _step = _Step.configure;
    if (kind == ImportSourceKind.iphoneBackup) _findBackups();
  }

  Future<void> _findBackups() async {
    final notes = <String>[];
    final found = await IPhoneBackupLocator.findBackups(onIssue: notes.add);
    if (!mounted) return;
    setState(() {
      _backups = found;
      _backupSearchNote = notes.isEmpty
          ? (found.isEmpty ? 'No backups found in the usual folders. Make one (steps above) or type the folder path.' : null)
          : notes.join('\n');
      if (found.length == 1 && _path.text.isEmpty) _path.text = found.first.path;
    });
  }

  static String _cleanPath(String raw) {
    var s = raw.trim();
    if (s.length >= 2 && (s.startsWith('"') && s.endsWith('"') || s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1);
    }
    if (s.startsWith('~/') || s == '~') {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      s = p.join(home, s.length > 2 ? s.substring(2) : '');
    }
    return s;
  }

  ImportSource _buildSource() {
    final path = _cleanPath(_path.text);
    switch (_kind!) {
      case ImportSourceKind.iphoneBackup:
        if (path.isEmpty) throw const ImportException('Choose an iPhone backup folder first.');
        return IPhoneBackupSource(path);
      case ImportSourceKind.macMessages:
        if (path.isEmpty) throw const ImportException('Enter the path to chat.db first.');
        final attachments = _cleanPath(_attachmentsPath.text);
        return IMessageDbSource(
          dbPath: path,
          displayName: 'Mac Messages',
          locator: MacAttachmentLocator(attachments.isEmpty ? p.join(p.dirname(path), 'Attachments') : attachments),
        );
      case ImportSourceKind.smsBackupRestore:
        if (path.isEmpty) throw const ImportException('Choose the sms-....xml backup file first.');
        return SmsBackupRestoreSource(path);
      case ImportSourceKind.androidDevice:
        return AndroidDeviceSmsSource(bridge: widget.androidBridge);
    }
  }

  Future<void> _scan() async {
    setState(() {
      _error = null;
      _step = _Step.scanning;
      _progress = null;
    });
    try {
      await _source?.dispose();
      final source = _source = _buildSource();
      final vcf = _cleanPath(_vcfPath.text);
      _engine = ImportEngine(contacts: vcf.isEmpty ? null : await ContactBook.fromVcfFile(vcf));
      final dir = widget.attachmentDirectory ?? defaultImportAttachmentDirectory();
      _options = ReadOptions(
        attachmentDirectory: dir,
        ownAddresses: _ownNumbers.text.split(RegExp(r'[,;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet(),
      );
      final token = _token = CancellationToken();
      final preview = await _engine!.preview(source, options: _options!, token: token, onProgress: _onProgress);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _step = _Step.preview;
      });
    } on ImportCancelled {
      if (mounted) setState(() => _step = _Step.configure);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ImportException ? e.toString() : 'Could not read this source: $e';
          _step = _Step.configure;
        });
      }
    }
  }

  Future<void> _import() async {
    final token = _token = CancellationToken();
    setState(() {
      _step = _Step.importing;
      _progress = null;
    });
    final summary = await _engine!.run(_source!, widget.sink, options: _options!, token: token, onProgress: _onProgress);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _step = _Step.done;
    });
  }

  void _onProgress(ImportProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  Future<void> _pick(TextEditingController controller, ImportPathKind kind, {List<String>? extensions}) async {
    final picked = await widget.pickPath?.call(kind, extensions: extensions);
    if (picked != null && mounted) setState(() => controller.text = picked);
  }

  // ---- UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _Step.importing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import chat history'),
          leading: _step == _Step.configure || _step == _Step.preview
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => setState(() => _step = _step == _Step.preview ? _Step.configure : _Step.choose),
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: kIsWeb ? _webUnsupported(context) : _body(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_step) {
      case _Step.choose:
        return _chooseView(context);
      case _Step.configure:
        return _configureView(context);
      case _Step.scanning:
        return _progressView(context, 'Checking your messages...', cancellable: true);
      case _Step.preview:
        return _previewView(context);
      case _Step.importing:
        return _progressView(context, 'Importing...', cancellable: true);
      case _Step.done:
        return _doneView(context);
    }
  }

  Widget _webUnsupported(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Importing chat history needs the desktop or mobile app; browsers cannot read backup files.'),
      );

  Widget _chooseView(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final options = <(ImportSourceKind, IconData, String, String)>[
      if (desktop)
        (
          ImportSourceKind.iphoneBackup,
          Icons.phone_iphone,
          'iPhone (iMessage & SMS)',
          'From an unencrypted iPhone backup on this Windows PC or Mac.',
        ),
      if (desktop)
        (
          ImportSourceKind.macMessages,
          Icons.laptop_mac,
          'Messages on a Mac',
          'Read the Mac Messages app history (chat.db).',
        ),
      (
        ImportSourceKind.smsBackupRestore,
        Icons.android,
        'Android / Google Messages',
        'From an "SMS Backup & Restore" backup file (.xml or .xml.zip).',
      ),
      if (Platform.isAndroid)
        (
          ImportSourceKind.androidDevice,
          Icons.sms,
          'Texts on this phone',
          'Read SMS/MMS directly from this Android phone.',
        ),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Where are your old messages?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Everything is read on this device. Nothing is uploaded by the importer.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final (kind, icon, title, subtitle) in options)
          Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _select(kind)),
            ),
          ),
      ],
    );
  }

  Widget _configureView(BuildContext context) {
    final kind = _kind!;
    final theme = Theme.of(context);
    final steps = importInstructions(kind, isMac: Platform.isMacOS);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_titleFor(kind), style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 11, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Text(steps[i])),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (kind == ImportSourceKind.iphoneBackup) ..._backupPicker(context),
        if (kind == ImportSourceKind.macMessages) ...[
          _pathField(_path, 'chat.db file', ImportPathKind.file, extensions: const ['db']),
          _pathField(_attachmentsPath, 'Attachments folder (optional)', ImportPathKind.directory),
        ],
        if (kind == ImportSourceKind.smsBackupRestore)
          _pathField(_path, 'Backup file (sms-....xml or .xml.zip)', ImportPathKind.file, extensions: const ['xml', 'zip']),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Optional: contact names and your number'),
          children: [
            _pathField(_vcfPath, 'Contacts file (.vcf) to show names', ImportPathKind.file, extensions: const ['vcf']),
            if (kind == ImportSourceKind.smsBackupRestore || kind == ImportSourceKind.androidDevice)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _ownNumbers,
                  decoration: const InputDecoration(
                    labelText: 'Your own phone number(s), comma separated',
                    helperText: 'Helps keep you out of group chat member lists.',
                  ),
                ),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _scan,
          icon: const Icon(Icons.search),
          label: const Text('Check messages'),
        ),
      ],
    );
  }

  List<Widget> _backupPicker(BuildContext context) {
    final backups = _backups;
    return [
      Row(
        children: [
          Expanded(child: Text('Backups on this computer', style: Theme.of(context).textTheme.titleSmall)),
          TextButton.icon(onPressed: _findBackups, icon: const Icon(Icons.refresh), label: const Text('Search again')),
        ],
      ),
      if (backups == null) const LinearProgressIndicator(),
      if (backups != null)
        RadioGroup<String>(
          groupValue: _path.text,
          onChanged: (v) => setState(() => _path.text = v ?? ''),
          child: Column(
            children: [
              for (final b in backups)
                RadioListTile<String>(
                  value: b.path,
                  title: Text(b.label),
                  subtitle: Text([
                    if (b.lastBackupDate != null) 'Backed up ${DateFormat.yMMMd().add_jm().format(b.lastBackupDate!.toLocal())}',
                    if (b.isEncrypted == true) 'Encrypted - cannot be read',
                  ].join(' · ')),
                ),
            ],
          ),
        ),
      if (_backupSearchNote != null)
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(_backupSearchNote!)),
      _pathField(_path, 'Or backup folder path', ImportPathKind.directory),
    ];
  }

  Widget _pathField(TextEditingController controller, String label, ImportPathKind kind, {List<String>? extensions}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Paste a path',
          suffixIcon: widget.pickPath == null
              ? null
              : IconButton(
                  icon: Icon(kind == ImportPathKind.directory ? Icons.folder_open : Icons.attach_file),
                  tooltip: 'Browse',
                  onPressed: () => _pick(controller, kind, extensions: extensions),
                ),
        ),
      ),
    );
  }

  Widget _progressView(BuildContext context, String title, {required bool cancellable}) {
    final progress = _progress;
    final fraction = progress?.fraction;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 10),
          Text(
            progress == null
                ? 'Starting...'
                : '${progress.phase}: ${NumberFormat.decimalPattern().format(progress.processed)}'
                    '${progress.total == null ? '' : ' of ${NumberFormat.decimalPattern().format(progress.total)}'}',
            textAlign: TextAlign.center,
          ),
          if (progress?.detail != null)
            Text(progress!.detail!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 20),
          if (cancellable)
            Center(
              child: OutlinedButton(
                onPressed: () => _token?.cancel(),
                child: const Text('Cancel'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewView(BuildContext context) {
    final pr = _preview!;
    final fmt = DateFormat.yMMMd();
    final n = NumberFormat.decimalPattern();
    final range = pr.earliest == null ? 'No messages found' : '${fmt.format(pr.earliest!.toLocal())} – ${fmt.format(pr.latest!.toLocal())}';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Ready to import', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _stat('Conversations',
            '${n.format(pr.threads)} (${n.format(pr.groupThreads)} group${pr.groupThreads == 1 ? '' : 's'})'),
        _stat('Messages', n.format(pr.messages)),
        if (pr.reactions > 0) _stat('Reactions', n.format(pr.reactions)),
        _stat('Photos & files', '${n.format(pr.attachments - pr.missingAttachments)} of ${n.format(pr.attachments)} available'),
        _stat('Dates', range),
        if (pr.byService.isNotEmpty)
          _stat('Types', pr.byService.entries.map((e) => '${_serviceName(e.key)} ${n.format(e.value)}').join(' · ')),
        if (pr.issues.isNotEmpty) _issues(pr.issues),
        const SizedBox(height: 16),
        Text(
          'Messages already imported earlier are skipped automatically.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: pr.messages + pr.reactions == 0 ? null : _import,
          icon: const Icon(Icons.download),
          label: Text('Import ${n.format(pr.messages)} messages'),
        ),
      ],
    );
  }

  Widget _doneView(BuildContext context) {
    final s = _summary!;
    final n = NumberFormat.decimalPattern();
    final theme = Theme.of(context);
    final headline = s.fatalError != null
        ? 'Import stopped'
        : s.cancelled
            ? 'Import cancelled'
            : 'Import complete';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(headline, style: theme.textTheme.titleLarge),
        if (s.fatalError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(s.fatalError!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 12),
        _stat('Conversations', n.format(s.threads)),
        _stat('New messages', n.format(s.messagesAdded)),
        _stat('Already imported (skipped)', n.format(s.duplicatesSkipped)),
        _stat('Photos & files saved', n.format(s.attachments)),
        if (s.missingAttachments > 0) _stat('Files not recoverable', n.format(s.missingAttachments)),
        _stat('Time', '${s.elapsed.inSeconds}s'),
        if (s.cancelled || s.fatalError != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Messages read so far were saved. Running the import again continues without duplicates.'),
          ),
        if (s.issues.isNotEmpty) _issues(s.issues),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.of(context).maybePop(s), child: const Text('Done')),
      ],
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _issues(List<ImportIssue> issues) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('${issues.length} note${issues.length == 1 ? '' : 's'}'),
        children: [
          for (final i in issues.take(50))
            ListTile(dense: true, leading: const Icon(Icons.info_outline, size: 18), title: Text(i.toString())),
        ],
      );

  static String _titleFor(ImportSourceKind kind) => switch (kind) {
        ImportSourceKind.iphoneBackup => 'Import from an iPhone backup',
        ImportSourceKind.macMessages => 'Import from Messages on a Mac',
        ImportSourceKind.smsBackupRestore => 'Import from Android',
        ImportSourceKind.androidDevice => 'Import texts on this phone',
      };

  static String _serviceName(MessageService s) => switch (s) {
        MessageService.iMessage => 'iMessage',
        MessageService.sms => 'SMS',
        MessageService.mms => 'MMS',
        MessageService.rcs => 'RCS',
        MessageService.unknown => 'Other',
      };
}

/// User-facing how-to steps per source (kept in sync with docs/IMPORT.md).
List<String> importInstructions(ImportSourceKind kind, {required bool isMac}) {
  switch (kind) {
    case ImportSourceKind.iphoneBackup:
      return [
        if (isMac)
          'Connect your iPhone to this Mac with a cable and open Finder. Click your iPhone in the sidebar.'
        else
          'Install "Apple Devices" from the Microsoft Store (or iTunes on older Windows). Connect your iPhone with a cable and open the app.',
        'On the iPhone, tap "Trust" and enter your passcode if asked.',
        'Choose "Back up all of the data on your iPhone to this computer". Make sure "Encrypt local backup" is NOT ticked.',
        'Click "Back Up Now" and wait until it finishes.',
        'The backup contains the messages stored on the phone. Photos the iPhone has offloaded to iCloud may be missing.',
        'Pick the backup below and click "Check messages".',
      ];
    case ImportSourceKind.macMessages:
      return [
        'Open System Settings > Privacy & Security > Full Disk Access and turn it on for Orbit (macOS protects the Messages folder).',
        'Quit and reopen Orbit.',
        'Keep the default path below (your Mac\'s chat.db) or paste the path to a copied chat.db.',
        'Click "Check messages".',
      ];
    case ImportSourceKind.smsBackupRestore:
      return [
        'On your Android phone, install "SMS Backup & Restore" by SyncTech from Google Play.',
        'Open it, tap "Set up a backup", turn on Messages (and turn on "Include MMS media" so photos come along). Back up to the phone or to Google Drive.',
        'Copy the "sms-<date>.xml" (or .xml.zip) file to this computer: via USB cable, Google Drive, or the app\'s "Transfer" option.',
        'Paste the file path below and click "Check messages".',
      ];
    case ImportSourceKind.androidDevice:
      return [
        'Orbit will ask for permission to read your text messages.',
        'Messages are read on this phone only.',
        'RCS chats appear only if Google Messages stored them in the phone\'s message database.',
      ];
  }
}
