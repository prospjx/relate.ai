import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Outcome of trying to start Firebase. [error] is set when the app has not
/// been configured with `flutterfire configure` or initialization failed.
class FirebaseStartup {
  const FirebaseStartup.ready() : error = null;
  const FirebaseStartup.failed(this.error);

  final String? error;

  bool get isReady => error == null;
}

Future<FirebaseStartup> startFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    try {
      // Keeps chat history readable offline. Must run before first use.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {
      // Settings can only be applied once; a hot restart may hit this.
    }
    return const FirebaseStartup.ready();
  } on UnsupportedError catch (e) {
    return FirebaseStartup.failed(e.message ?? e.toString());
  } catch (e) {
    return FirebaseStartup.failed(e.toString());
  }
}
