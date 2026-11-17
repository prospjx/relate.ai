import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/screens/setup_screen.dart';
import 'package:orbit/services/sticker_pack.dart';

void main() {
  testWidgets('setup screen explains how to connect Firebase', (tester) async {
    var retried = 0;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SetupScreen(
        error: 'Firebase is not configured for this app yet.',
        onRetry: () async => retried++,
      ),
    ));
    expect(find.text('Connect Orbit to Firebase'), findsOneWidget);
    expect(find.textContaining('flutterfire configure'), findsWidgets);
    expect(find.text('Firebase is not configured for this app yet.'),
        findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });

  test('every sticker has an asset file', () {
    for (final sticker in stickerPack) {
      expect(File(sticker.asset).existsSync(), isTrue, reason: sticker.asset);
    }
  });
}
