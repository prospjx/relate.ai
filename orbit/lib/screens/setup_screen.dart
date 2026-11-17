import 'package:flutter/material.dart';

import '../theme/orbit_theme.dart';

/// Shown when Firebase has not been configured for this build.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, this.error, required this.onRetry});

  final String? error;
  final Future<void> Function() onRetry;

  static const _steps = [
    'Install the FlutterFire CLI: dart pub global activate flutterfire_cli',
    'In the orbit folder, run: flutterfire configure',
    'Pick your Firebase project and the platforms you want (web, Windows, Android, iOS).',
    'In the Firebase console, turn on Authentication > Email/Password, create a Firestore database, and set up Storage.',
    'Deploy the rules: firebase deploy --only firestore:rules,firestore:indexes,storage',
    'Restart the app.',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 40, color: OrbitColors.accent),
                const SizedBox(height: 16),
                Text('Connect Orbit to Firebase',
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Orbit uses Firebase for accounts, messages, and media. '
                  'This build has not been connected to a Firebase project yet.',
                  style: TextStyle(color: OrbitColors.soft, height: 1.5),
                ),
                const SizedBox(height: 20),
                for (var i = 0; i < _steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('${i + 1}.',
                              style: const TextStyle(color: OrbitColors.soft)),
                        ),
                        Expanded(
                          child: SelectableText(_steps[i],
                              style: const TextStyle(height: 1.45)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Full steps are in orbit/README.md.',
                  style: TextStyle(color: OrbitColors.soft),
                ),
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OrbitColors.raised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OrbitColors.line),
                    ),
                    child: SelectableText(
                      error!,
                      style: const TextStyle(
                          color: OrbitColors.soft, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
