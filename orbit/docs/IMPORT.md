# Importing chat history into Orbit

Orbit can bring in your old text messages from an iPhone (iMessage and SMS) and from Android (Google Messages and other SMS apps), so earlier conversations show up in Orbit.

**Privacy:** the importer runs entirely on your own computer or phone. It reads the backup file you choose and never uploads message content anywhere. It hands the messages to Orbit's storage (the "import sink"), and from then on that storage decides where the data lives. If Orbit syncs chats to the cloud, imported chats are synced too, just like chats you send in Orbit.

| Where your messages are | What you need | Works on |
| --- | --- | --- |
| iPhone | An **unencrypted** iPhone backup on a Windows PC or Mac | Orbit for Windows / Mac |
| Mac Messages app | Full Disk Access for Orbit | Orbit for Mac (or a copied `chat.db` on Windows) |
| Android phone | A backup file from the free **SMS Backup & Restore** app | Orbit for Windows / Mac / Android |
| Android phone (direct) | Orbit installed outside Google Play, with SMS permission | Orbit for Android (special builds) |

You can run an import more than once, or import the same messages from two sources. Messages already in Orbit are recognized and skipped.

---

## iPhone (iMessage and SMS) via a computer backup

Apple has no export button for Messages. A local iPhone backup does contain the Messages database (`sms.db`) and its photos and videos, and Orbit can read those backups.

### On Windows

1. Install **Apple Devices** from the Microsoft Store (on older Windows versions, **iTunes** works too).
2. Connect the iPhone with a cable and open Apple Devices. On the iPhone, tap **Trust** and enter your passcode.
3. Under **Backups**, choose **Back up all of the data on your iPhone to this PC**.
4. Make sure **Encrypt local backup** is **not** ticked. If it is ticked, untick it; you will need the backup password.
5. Click **Back Up Now** and wait until it finishes. A large phone can take an hour.
6. In Orbit, open **Import chat history**, choose **iPhone (iMessage & SMS)**, and pick the backup from the list.

Orbit looks in `%USERPROFILE%\Apple\MobileSync\Backup` and `%APPDATA%\Apple Computer\MobileSync\Backup`, the two folders Apple documents. If your backup is somewhere else, paste that folder's path. Use the folder that contains `Manifest.db` and `Info.plist`.

### On a Mac

1. Connect the iPhone and open **Finder**. Click the iPhone in the sidebar, then the **General** tab.
2. Choose **Back up all of the data on your iPhone to this Mac**, untick **Encrypt local backup**, and click **Back Up Now**.
3. macOS protects the backup folder, so give Orbit access first: **System Settings → Privacy & Security → Full Disk Access**, turn on Orbit, then reopen Orbit.
4. In Orbit, choose **iPhone (iMessage & SMS)** and pick the backup. Orbit looks in `~/Library/Application Support/MobileSync/Backup`.

### Encrypted backups are not supported

In an encrypted backup, every file, including the index (`Manifest.db`), is AES-encrypted with keys protected by your backup password. Decrypting it would mean asking for that password and bundling cryptography code, so Orbit does not do it. Orbit detects encrypted backups and explains how to make an unencrypted one. You can turn encryption back on after importing.

---

## Messages on a Mac

If your Mac's Messages app holds your history (for example with Messages in iCloud turned on), Orbit can read it directly.

1. **System Settings → Privacy & Security → Full Disk Access**: turn on Orbit, then quit and reopen it. Without this, macOS blocks access to `~/Library/Messages`.
2. In Orbit, choose **Messages on a Mac**. The path defaults to `~/Library/Messages/chat.db`, and photos are read from `~/Library/Messages/Attachments`.
3. Click **Check messages**, review the counts, then **Import**.

**Importing a Mac's messages on Windows:** copy the whole `~/Library/Messages` folder from the Mac to the PC. On the Mac you need Full Disk Access for Finder or Terminal to copy it. In Orbit for Windows, choose **Messages on a Mac** and paste the copied `chat.db` path. Set the attachments folder to the copied `Attachments` folder.

Orbit always works on a private copy of `chat.db`, including its `-wal` journal so the newest messages are included. It never changes the original.

---

## Android / Google Messages

Google gives you no way to download your texts:

- **Google Takeout** does not offer Google Messages as an export option. Its help page lists products like Mail, Drive, Photos and YouTube, and Messages isn't one of them.
- The **Google Messages** backup inside your phone's Google One / Drive backup can only be restored onto another Android phone. It can't be downloaded as a file.

The dependable route is the free **SMS Backup & Restore** app by SyncTech, which saves texts to a documented XML file.

### Make the backup (on the phone)

1. Install **SMS Backup & Restore** (SyncTech Pty Ltd) from Google Play.
2. Open it and tap **Set up a backup**. Turn on **Messages**; turning off **Phone calls** is optional.
3. Under advanced options, make sure **MMS media** is included, so photos and videos come along.
4. Choose where to save: the phone itself, or Google Drive or Dropbox.
5. Tap **Back up now**.

### Copy it to your computer

- **Google Drive:** open drive.google.com on the computer and download the file named `sms-<date>.xml` (or `.xml.zip`).
- **USB cable (Windows):** connect the phone, choose **File transfer** on the phone, open it in File Explorer, and copy the file from the `SMSBackupRestore` folder.
- **USB cable (Mac):** use Android File Transfer or OpenMTP, then copy the same file.

### Import

In Orbit, choose **Android / Google Messages** and pick or paste the `sms-….xml` or `.xml.zip` file. Optionally, open **Optional: contact names and your number** and fill in:

- **Your own phone number(s)**: this keeps you out of group member lists. Android stores your own number inside group MMS, and Orbit can't always tell it apart from the other members.
- **A contacts file (.vcf)**, so conversations show names instead of numbers (see "Contact names" below).

Very large backups are fine: the file is streamed rather than loaded into memory, and photos are decoded straight to disk. Zip files protected by a password aren't supported. Unzip them first with your SMS Backup & Restore password.

### Importing directly on the Android phone

A special Orbit build can read texts straight from the phone's message store, with no backup file needed. It asks for the **SMS** permission. Google Play only lets apps that are (or can become) the default SMS app hold this permission. The Play Store version of Orbit therefore uses the backup-file route, and direct import is for sideloaded or enterprise builds. Developer details are below.

---

## What transfers

| | iPhone backup / Mac | SMS Backup & Restore file | Android direct |
| --- | --- | --- | --- |
| Text messages with original date and time | Yes | Yes | Yes |
| Who sent each message (you or them) | Yes | Yes | Yes |
| 1:1 and group chats | Yes (group names too) | Yes | Yes |
| Photos, videos, voice notes, files | Yes, if they're in the backup / on the Mac | Yes, if "MMS media" was on | Yes |
| iMessage tapbacks (❤️ 👍 👎 😂 ‼️ ❓, emoji) | Yes, as reactions | n/a | n/a |
| Read / unread state | Yes (and when it was read) | Yes | Yes |
| SMS / MMS / iMessage / RCS label | Yes | Yes (RCS detected heuristically) | Yes (RCS detected heuristically) |
| RCS chats (Google Messages "chat" messages) | n/a | Partly; see below | Partly; see below |
| Contact names | From a .vcf file | From the backup or a .vcf | From a .vcf |

## What does not transfer, and why

- **Encrypted iPhone backups:** see above.
- **Photos the iPhone has offloaded to iCloud**, or that were never downloaded: they aren't in the backup or on the Mac. Orbit imports the message and marks the photo as unavailable.
- **iMessage effects, stickers, Memoji, app/game messages, polls, edit history, "unsent" messages:** these don't map to plain messages, so they're skipped and counted in the import notes. Group events other than renames (people joining or leaving) are skipped too. A rename is imported as a small "named the conversation" note.
- **RCS chats from Google Messages:** Google Messages keeps RCS chats in its own private database. They're only recoverable when Google Messages also writes them into Android's shared SMS/MMS store. SMS Backup & Restore then shows them with addresses ending in `@rcs.google.com`, and Orbit labels them RCS. How complete that is depends on the phone and Google Messages version. RCS reactions, replies, typing and read receipts don't transfer. Orbit can't check how many RCS messages were missed.
- **Samsung Messages** chat (RCS) messages: imported when SMS Backup & Restore includes them (it marks them with `s_chat="1"`).
- **Drafts** and **call logs** aren't imported.
- **Two separate group chats with exactly the same people on Android** become one conversation, because Android identifies group texts only by their members.

## Contact names

Message backups mostly contain phone numbers and emails, not names. To show names, export your contacts as a **.vcf** file and choose it under the optional section:

- **iPhone:** open iCloud.com → Contacts → select all → Export vCard. On a Mac you can also use Contacts → File → Export → Export vCard.
- **Android / Google:** go to contacts.google.com → Export → vCard.

Numbers are matched on their last 10 digits, so "+1 (555) 123-4567" and "555-123-4567" match.

## Known limits

- **Full Disk Access (Mac):** without it, macOS blocks both `~/Library/Messages` and the iPhone backup folder, and Orbit shows a permission error.
- **iPhone and Mac imports run only in the desktop apps** (Windows, Mac, Linux). They use the SQLite library built into the operating system (`winsqlite3.dll` on Windows 10+, `libsqlite3` on macOS and Linux). Android doesn't let apps use its built-in SQLite, so Orbit for Android only offers the Android sources.
- **Play Store SMS policy:** direct on-phone import needs READ_SMS, which Google Play restricts to default SMS apps.
- **Old iPhone backups** from before iOS 10 have no `Manifest.db`. Orbit tries the computed file names and usually still finds `sms.db`, but this is untested.
- Messages missing a date or any participant are skipped, and the import notes say how many.

---

## For developers: integrating the importer

All code lives in `lib/import/`. Import everything with `import 'package:orbit/import/import.dart';`.

### Dependencies

**No `pubspec.yaml` changes are required** with the current `pubspec.yaml`:

- `ImportScreen` uses `file_picker` (already a dependency) for its Browse buttons. If `file_picker` is ever removed, delete `filePickerImportPath` in `ui/import_screen.dart` and pass `pickPath: null`. Typed and pasted paths always work.
- SQLite access goes through `dart:ffi` to the OS library (`util/sqlite.dart`), so `sqflite`, `sqflite_common_ffi` and `package:ffi` aren't needed. XML, zip, SHA-1, plist and vCard parsing are pure Dart.
- `path`, `intl` and `flutter` are used, all already present.
- Optional: if the app adds `path_provider`, pass `attachmentDirectory: '${(await getApplicationSupportDirectory()).path}/imported_attachments'`. Without it, `defaultImportAttachmentDirectory()` uses `%APPDATA%\Orbit\…` on Windows, `~/Library/Application Support/Orbit/…` on macOS, and a best guess on mobile.

### 1. Implement `ImportSink`

```dart
abstract class ImportSink {
  Future<void> begin(String sourceName) async {}
  Future<void> upsertThread(ImportedThread thread);
  Future<AppendResult> appendMessages(String threadKey, List<ImportedMessage> messages);
  Future<void> end(ImportSummary summary) async {}
}
```

The contract, also documented in `lib/import/sink.dart`:

- `upsertThread` runs before a thread's first messages and can repeat for the same `thread.key`: merge participants, don't duplicate. Map `thread.key` to your conversation ID. It's stable: `dm:<normalized address>`, `group:<sorted addresses>` or `imsg-group:<chat_identifier>`.
- `appendMessages` must be **idempotent on `message.key`**. Skip keys you already stored and return `AppendResult(inserted:, skipped:)`. Store `key` in a unique column or field, or use it as the document ID. Batches arrive sorted by `sentAt` within a thread.
- `ImportedAttachment.localPath` points into the importer's attachment folder. Copy or upload the file during `appendMessages` if your storage needs it elsewhere, for example Firebase Storage. `isAvailable == false` means the file couldn't be recovered; `missingReason` says why.
- `kind == ImportedMessageKind.reaction`: apply `reaction` (an emoji) from the sender to the message whose key is `reactionTargetKey`, or remove it if `reactionRemoved`. You can also simply ignore reactions.
- `kind == system`: a conversation event; show it as a centered note.
- Map `isFromMe` to your "me" sender, and otherwise use `senderAddress`, which is always set for incoming group messages.

`InMemoryImportSink` in `sink.dart` is a complete reference implementation.

### Models

Defined in `lib/import/models.dart`:

- `ImportedThread { key, participants: [ImportedParticipant{address, displayName?}], isGroup, service, title?, sourceId? }`. Participants never include the device owner.
- `ImportedMessage { key, threadKey, sentAt (UTC), isFromMe, senderAddress?, service (sms|mms|rcs|iMessage|unknown), text, attachments, isRead, readAt?, kind, reactionTargetKey?, reaction?, reactionRemoved, subject? }`.
- `ImportedAttachment { fileName, mimeType, localPath?, sizeBytes?, missingReason? }`.
- `ImportPreview`, `ImportProgress`, `ImportSummary`, `ImportIssue`.

### 2. Open the screen

One line, from wherever the app offers "Import chats" (for example a settings menu):

```dart
Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(sink: OrbitImportSink(appState))));
```

`ImportScreen` pops with the `ImportSummary` after a run. Optional parameters:

- `attachmentDirectory`
- `pickPath` (pass `null` to hide the Browse buttons)
- `initialSource`
- `androidBridge`

To drive an import without the UI:

```dart
final summary = await ImportEngine(contacts: await ContactBook.fromVcfFile(vcf))
    .run(SmsBackupRestoreSource(path), sink, options: ReadOptions(attachmentDirectory: dir));
```

### 3. Optional: Android on-device import (native side)

`AndroidDeviceSmsSource` talks to the `orbit/sms_import` MethodChannel:

| Method | Arguments | Returns |
| --- | --- | --- |
| `status` | none | `{hasPermission, isDefaultSmsApp, smsCount, mmsCount}` |
| `requestPermission` | none | `bool` |
| `querySms` | `{afterId, limit}` | rows of `content://sms` columns, ascending `_id` |
| `queryMms` | `{afterId, limit}` | rows of `content://mms` columns with `date` converted to **milliseconds**, plus `parts` (`content://mms/part` rows without `_data`), `addrs` (`content://mms/<id>/addr` rows) and `address` (thread recipients joined with `~`) |
| `copyPart` | `{partId, destinationPath}` | bytes copied from `content://mms/part/<id>` |

The column names deliberately match SMS Backup & Restore's attributes, so both Android sources share `SmsRecordMapper` and generate **identical message keys**. Importing from a backup and from the phone never creates duplicates.

The Kotlin side is `android/app/src/main/kotlin/com/orbit/orbit/OrbitSmsImportPlugin.kt`, registered in `MainActivity.configureFlutterEngine`, and `READ_SMS` is declared in `AndroidManifest.xml`. A Google Play build would have to remove the permission and the plugin unless Orbit becomes the default SMS app. Without the native side, the source reports a friendly "not included in this build" error.

The Kotlin side is untested. It pages with `LIMIT` in the sort order, which the Telephony provider accepts on the devices we know of. If a device rejects it, switch to `ContentResolver.QUERY_ARG_LIMIT` query arguments (API 26+).

### Sources at a glance

| Class | Input |
| --- | --- |
| `IMessageDbSource(dbPath:, locator:)` | macOS `chat.db` or iOS `sms.db` (any copy). Use `MacAttachmentLocator` for Mac attachments. |
| `IPhoneBackupSource(backupDir)` | Unencrypted iPhone backup folder. `IPhoneBackupLocator.findBackups()` lists the backups in Apple's default folders. |
| `SmsBackupRestoreSource(path)` | `sms-*.xml` or `sms-*.xml.zip` |
| `AndroidDeviceSmsSource(bridge:)` | Live Android SMS/MMS providers |

Every source supports cancellation (`CancellationToken`), progress callbacks and per-item issues. Fatal problems become `ImportSummary.fatalError` with a user-readable message and hint, and messages read before a failure or cancel are still saved.

### Verification status

- **Covered by automated tests** (`flutter test test/import`, synthetic fixtures only):
  - chat.db / sms.db parsing, including both Apple date formats, attributedBody text, tapbacks, group detection, attachments, renames and older schemas
  - iPhone backup discovery, Manifest.db lookups and encrypted-backup detection
  - SMS Backup & Restore XML and `.xml.zip` parsing (SMS, group MMS, image part, RCS group, drafts, emoji entities, truncated files)
  - the dedupe keys, including identical keys from the XML and Android sources
  - cancellation, the MethodChannel contract and the screen flow
- **Checked against public documentation:** the SMS Backup & Restore field meanings (SyncTech's spec page), Apple's backup folder locations (support.apple.com/108809), the `sms.db` file ID (a test computes SHA-1 of `HomeDomain-Library/SMS/sms.db`), and the tapback codes (2000–2007 added, 3000–3007 removed, as in the open-source imessage-exporter).
- **Not yet tried on real user data:**
  - real iPhone backups and Mac chat.db files from different iOS/macOS versions (the attributedBody decoder is a best-effort heuristic)
  - real SMS Backup & Restore exports from various phones
  - the Kotlin plugin
  - macOS SQLite loading and Full Disk Access prompts (development and tests ran on Windows with `winsqlite3.dll`)
