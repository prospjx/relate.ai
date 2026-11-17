import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/import/import.dart';
import 'package:path/path.dart' as p;

import 'fixtures/builders.dart';

/// Lets real file I/O run while the (animated) progress screen is shown.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('walks through choose -> instructions -> preview -> import -> summary', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('orbit_screen_test_'));
    addTearDown(() => tmp!.deleteSync(recursive: true));
    final sink = InMemoryImportSink();
    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(sink: sink, pickPath: null, attachmentDirectory: p.join(tmp!.path, 'att')),
    ));

    expect(find.text('Where are your old messages?'), findsOneWidget);
    expect(find.text('iPhone (iMessage & SMS)'), findsOneWidget);
    await tester.tap(find.text('Android / Google Messages'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SMS Backup & Restore'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '"${File(fixturePath('sms_backup_sample.xml')).absolute.path}"');
    await tester.tap(find.text('Check messages'));
    await pumpUntilFound(tester, find.text('Ready to import'));

    expect(find.text('Ready to import'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    // No owner number entered, so the RCS group that lists the owner stays separate.
    expect(find.text('4 (2 groups)'), findsOneWidget);
    await tester.tap(find.text('Import 6 messages'));
    await pumpUntilFound(tester, find.text('Import complete'));

    expect(find.text('Import complete'), findsOneWidget);
    expect(sink.messageCount, 6);
  });

  testWidgets('shows a readable error for a wrong file', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(sink: InMemoryImportSink(), pickPath: null, initialSource: ImportSourceKind.smsBackupRestore),
    ));
    await tester.enterText(find.byType(TextField).first, p.join('no', 'such', 'file.xml'));
    await tester.tap(find.text('Check messages'));
    await pumpUntilFound(tester, find.textContaining('File not found'));
    expect(find.textContaining('File not found'), findsOneWidget);
  });
}
