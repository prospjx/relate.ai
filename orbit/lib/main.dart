import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/firebase_bootstrap.dart';
import 'data/services.dart';
import 'screens/auth_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/setup_screen.dart';
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
    return MaterialApp(
      title: 'Orbit',
      debugShowCheckedModeBanner: false,
      theme: buildOrbitTheme(),
      home: services == null
          ? SetupScreen(error: _startup.error, onRetry: _retry)
          : Provider<OrbitServices>.value(
              value: services,
              child: const AuthGate(),
            ),
    );
  }
}

/// Shows sign in when signed out, otherwise the inbox for that user.
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
        if (user == null) return const AuthScreen();
        return ChangeNotifierProvider<Session>(
          key: ValueKey(user.uid),
          create: (_) => Session(
            services: services,
            uid: user.uid,
            email: user.email ?? '',
          )..start(displayName: user.displayName),
          child: const InboxScreen(),
        );
      },
    );
  }
}
