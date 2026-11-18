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
    final palette = MessengerPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              shrinkWrap: true,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    Icons.cloud_off_rounded,
                    size: 36,
                    color: palette.secondaryInk,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connect Orbit to Firebase',
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Orbit uses Firebase for accounts, messages, and media. '
                  'This build has not been connected to a Firebase project yet.',
                  style: TextStyle(
                    color: palette.secondaryInk,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                for (var i = 0; i < _steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}.',
                            style: TextStyle(
                              color: palette.secondaryInk,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            _steps[i],
                            style: TextStyle(
                              color: palette.ink,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Full steps are in orbit/README.md.',
                  style: TextStyle(
                    color: palette.secondaryInk,
                    fontSize: 13.5,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.hairline),
                    ),
                    child: SelectableText(
                      error!,
                      style: TextStyle(
                        color: palette.secondaryInk,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
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
