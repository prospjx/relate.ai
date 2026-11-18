import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/models/models.dart';
import 'package:orbit/screens/setup_screen.dart';
import 'package:orbit/services/sticker_pack.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/avatar.dart';
import 'package:orbit/widgets/message_bubble.dart';

void main() {
  testWidgets('setup screen explains how to connect Firebase', (tester) async {
    var retried = 0;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
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

  testWidgets('messenger theme renders light and dark bubbles and avatars',
      (tester) async {
    final msg = Message(
      id: 'm1',
      conversationId: 'c1',
      senderId: 'u2',
      senderName: 'Alex',
      kind: MessageKind.text,
      text: 'See you at 5',
      sentAt: DateTime(2026, 11, 17, 17, 0),
    );

    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              const AvatarBubble(name: 'Alex Morgan', online: true),
              MessageBubble(
                message: msg,
                mine: false,
                myUid: 'u1',
                showSender: true,
                onOpenActions: () {},
                onToggleReaction: (_) {},
                onShowReactions: () {},
              ),
              MessageBubble(
                message: msg,
                mine: true,
                myUid: 'u2',
                showSender: false,
                onOpenActions: () {},
                onToggleReaction: (_) {},
                onShowReactions: () {},
              ),
            ],
          ),
        ),
      ));
      expect(find.text('AM'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('See you at 5'), findsNWidgets(2));
    }
  });

  test('every sticker has an asset file and legacy orbit sticker still resolves',
      () {
    expect(stickerPack.any((s) => s.id == 'orbit'), isFalse);
    expect(stickerById('orbit')?.asset, 'assets/stickers/orbit.svg');
    expect(File('assets/stickers/orbit.svg').existsSync(), isTrue);
    for (final sticker in stickerPack) {
      expect(File(sticker.asset).existsSync(), isTrue, reason: sticker.asset);
    }
  });
}
