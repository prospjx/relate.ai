import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/firebase_bootstrap.dart';
import 'data/services.dart';
import 'screens/auth_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/setup_screen.dart';
import 'services/sms_sync.dart';
import 'state/session.dart';
import 'theme/orbit_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startup = await startFirebase();
  runApp(OrbitApp(startup: startup));
}

class OrbitApp extends StatefulWidget {
  const OrbitApp({super.key, required this.startup});

  final FirebaseStartup startup;

  @override
  State<OrbitApp> createState() => _OrbitAppState();
}

class _OrbitAppState extends State<OrbitApp> {
  late FirebaseStartup _startup = widget.startup;
  OrbitServices? _services;

  OrbitServices? get _readyServices {
    if (!_startup.isReady) return null;
    return _services ??= OrbitServices.firebase();
  }

  Future<void> _retry() async {
    final result = await startFirebase();
    if (mounted) setState(() => _startup = result);
  }

  @override
  Widget build(BuildContext context) {
    final services = _readyServices;
    if (services == null) {
      return orbitApp(SetupScreen(error: _startup.error, onRetry: _retry));
    }
    return Provider<OrbitServices>.value(
      value: services,
      child: const AuthGate(),
    );
  }
}

/// Providers sit above [MaterialApp] so every pushed route can read them.
Widget orbitApp(Widget home) => MaterialApp(
      title: 'Messages',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: home,
    );

/// Shows sign in when signed out, otherwise the inbox for that user.
/// Signing in or out swaps the whole app, so no screen of the previous user
/// stays on the navigation stack.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.read<OrbitServices>();
    return StreamBuilder<User?>(
      stream: services.auth.authStateChanges(),
      initialData: services.auth.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return orbitApp(const AuthScreen());
        return SignedInScope(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

/// Owns everything tied to the signed-in user for as long as they stay
/// signed in.
class SignedInScope extends StatefulWidget {
  const SignedInScope({super.key, required this.user});

  final User user;

  @override
  State<SignedInScope> createState() => _SignedInScopeState();
}

class _SignedInScopeState extends State<SignedInScope> {
  late final Session _session;
  late final SmsSync _smsSync;

  @override
  void initState() {
    super.initState();
    final services = context.read<OrbitServices>();
    final user = widget.user;
    _session = Session(services: services, uid: user.uid, email: user.email ?? '')
      ..start(displayName: user.displayName);
    _smsSync = SmsSync.forUser(
      services: services,
      uid: user.uid,
      displayName: () => _session.displayName,
    );
  }

  @override
  void dispose() {
    _smsSync.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: _session),
        ChangeNotifierProvider<SmsSync>.value(value: _smsSync),
      ],
      child: orbitApp(const InboxScreen()),
    );
  }
}
