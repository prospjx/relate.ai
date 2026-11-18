# Orbit

A messenger built with Flutter and Firebase. Runs on Windows, the web (Chrome and Edge), Android, and iOS.

AI features, the blue orb, events, and relationship health are intentionally out for now.

## Features

**Accounts**

- Sign up and sign in with email and password
- Password reset by email
- Profiles with display name, about text, optional phone, and profile picture
- Online status and "last seen"

**Messaging**

- One-to-one chats, started by searching for someone's email or name
- Group chats: create, name, add or remove members, see the member list, leave
- Full message history, loaded 40 at a time as you scroll up, and readable offline
- A timestamp on every message, plus day separators (Today, Yesterday, weekday, date)
- Edit your own text messages (shows "edited")
- Delete your own messages for everyone (leaves "This message was deleted")
- Reactions (👍 ❤️ 😂 😮 😢 🙏), with counts and who reacted
- Unread markers in the inbox

**Media**

- Photos (with a full-screen viewer), videos, voice messages (record and play), and documents
- GIFs: search via Giphy when an API key is configured, or send a GIF file from your device
- Stickers from a built-in pack of 8 SVG stickers (no external service)

**Import old chats**

- The download button in the inbox imports history from an iPhone backup, a Mac's Messages database, or an SMS Backup & Restore export of Google Messages. See `docs/IMPORT.md`.
- Imported chats keep their original dates, senders, group names, photos and videos, and tapbacks. Running an import again skips messages already imported.
- Not available on the web build, which can't read local backup files.
- On Android, "Sync texts from this phone" (inbox prompt or Profile) copies every SMS/MMS once, then picks up new ones whenever the app is open or brought back to the foreground. Synced texts show up on every device you sign in on. Requires the sideloaded APK: Google Play only grants the SMS permission to default texting apps.

### Platform notes

| Feature | Windows | Web | Android / iOS |
| --- | --- | --- | --- |
| Video playback | Opens in your default player (`video_player` has no Windows support) | Inline | Inline |
| Camera capture | Not available; choose a file instead | Not available; choose a file instead | Yes |
| Voice recording | Yes (`record`) | Yes (browser asks for the microphone) | Yes (needs mic permission, see below) |

Firebase on Windows uses the FlutterFire desktop plugins, which Firebase supports for development but not for production releases.

## Set up Firebase

The app builds without any Firebase config. Until you connect it, it opens on a setup screen.

1. **Create or choose a project** at <https://console.firebase.google.com>.
2. **Install the CLIs** (once):

   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   ```

3. **Generate the config.** In the `orbit` folder:

   ```bash
   flutterfire configure
   ```

   Pick your project and the platforms you want (web, windows, android, ios). This overwrites `lib/firebase_options.dart`, which is only a placeholder in this repo.
4. **Turn on Authentication.** Go to Authentication, then Sign-in method, and enable **Email/Password**.
5. **Create the Firestore database.** Go to Firestore Database and create it in production mode, in the region of your choice.
6. **Set up Storage.** Go to Storage and select Get started.
7. **Deploy the rules and indexes.** In the `orbit` folder:

   ```bash
   firebase use --add            # select the same project
   firebase deploy --only firestore:rules,firestore:indexes,storage
   ```

   The Storage rules check chat membership in Firestore. On the first deploy, the CLI asks you to grant Storage access to Firestore; accept it.
8. **Optional: set CORS for web.** Images fall back to an `<img>` tag on web, so this is optional, but it avoids console noise:

   ```bash
   gsutil cors set storage.cors.json gs://YOUR_BUCKET
   ```

Files in this folder:

- `firestore.rules`: users can edit only their own profile. Chats and messages are readable only by members. Only the sender can edit or delete a message, and each person can change only their own reaction.
- `storage.rules`: anyone signed in can read avatars, but only the owner can write theirs. Chat files are limited to conversation members, with a 50 MB cap.
- `firestore.indexes.json`: the inbox index (`memberIds` contains, `updatedAt` descending).
- `firebase.json`: points the Firebase CLI at those files.

## GIF search (optional)

GIF search uses the Giphy API. Get a key at <https://developers.giphy.com>, then pass it at build or run time:

```bash
flutter run -d chrome --dart-define=GIPHY_API_KEY=your_key
flutter build web --dart-define=GIPHY_API_KEY=your_key
```

Without a key, the GIF sheet says search is off and still lets you send a GIF file.

## Run

```bash
cd orbit
flutter pub get
flutter run -d windows
flutter run -d chrome
```

The Android manifest already requests internet and microphone access. This repo has no `ios/` folder; if you add one with `flutter create --platforms=ios .`, add `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`. Firebase Auth needs Android `minSdk` 23 or higher.

## Check

```bash
flutter analyze
flutter test
flutter build windows
flutter build web
```

Tests use `fake_cloud_firestore` and `firebase_auth_mocks`, so they don't need a Firebase project.

## Code layout

- `lib/models/`: `UserProfile`, `Conversation`, `LastMessage`, `Message`, `Attachment`, `Participant`, plus Firestore encoding helpers in `codec.dart`
- `lib/data/`: the repositories, which are the only code that talks to Firebase:
  - `auth_repository.dart`
  - `user_repository.dart`
  - `chat_repository.dart`
  - `media_repository.dart`
  - `firebase_bootstrap.dart`: guarded startup and offline persistence
  - `services.dart`: the container the UI reads from
- `lib/services/`: presence heartbeat, GIF search, voice recording, file picking, sticker pack, and platform capabilities
- `lib/state/session.dart`: the signed-in user's live profile and presence
- `lib/screens/` and `lib/widgets/`: the UI
- `lib/import/`: chat history import (see `docs/IMPORT.md`); `lib/data/orbit_import_sink.dart` writes it into Firestore

### Firestore data model

- `users/{uid}`:
  - `uid`, `displayName`, `displayNameLower`, `email`, `emailLower`, `about`, `phone`, `photoUrl`
  - `online`, `lastSeen` (presence; a heartbeat older than 2 minutes counts as offline)
  - `createdAt`
- `conversations/{id}`:
  - `type` (`direct` or `group`), `name`, `photoUrl`, `memberIds`, `adminIds`
  - `createdBy`, `createdAt`, `updatedAt`
  - `lastMessage` (a summary of the newest message)
  - `lastReadAt` (a map from uid to the time that member last read the chat)
  - `externalParticipants`, `importSource`, `importKey`
  - Direct chats use the id `dm_<uidA>_<uidB>`, with the two uids sorted.
- `conversations/{id}/messages/{messageId}`:
  - `kind`, `sentAt`, `senderId`, `senderAddress`, `senderName`, `text`, `attachments[]`
  - `editedAt`, `deleted`, `deletedAt`
  - `reactions` (a map from uid to emoji)
  - `imported`, `importedBy`, `importSource`, `importKey`, `createdAt`
- Storage paths:
  - `avatars/{uid}/…`
  - `chats/{conversationId}/{uploaderUid}/…`

Presence uses a Firestore heartbeat every 60 seconds instead of the Realtime Database's `onDisconnect`. If the app is killed, the user shows as offline within 2 minutes.
