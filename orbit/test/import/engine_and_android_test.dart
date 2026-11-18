import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/import/import.dart';
import 'package:orbit/import/util/xml_pull.dart';
import 'package:path/path.dart' as p;

import 'fixtures/builders.dart';

/// Serves the XML fixture's records as if they came from the Android
/// content providers (same column names; MMS date already in ms).
class FakeBridge implements AndroidSmsBridge {
  FakeBridge(this.sms, this.mms, {this.granted = true});

  final List<Map<String, String>> sms;
  final List<Map<String, Object?>> mms;
  bool granted;
  int permissionRequests = 0;
  final copied = <String>[];

  @override
  Future<AndroidSmsStatus> status() async =>
      AndroidSmsStatus(hasPermission: granted, smsCount: sms.length, mmsCount: mms.length);

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<List<Map<String, String>>> querySms({required int afterId, required int limit}) async =>
      sms.where((r) => int.parse(r['_id']!) > afterId).take(limit).toList();

  @override
  Future<List<Map<String, Object?>>> queryMms({required int afterId, required int limit}) async =>
      mms.where((r) => int.parse(r['_id'] as String) > afterId).take(limit).toList();

  @override
  Future<void> copyPart({required String partId, required String destinationPath}) async {
    copied.add(partId);
    await File(destinationPath).writeAsBytes(base64.decode(tinyPngBase64));
  }
}

Future<FakeBridge> bridgeFromFixture() async {
  final sms = <Map<String, String>>[];
  final mms = <Map<String, Object?>>[];
  Map<String, Object?>? current;
  var id = 0;
  final tokens = xmlTokens(Stream.value(await File(fixturePath('sms_backup_sample.xml')).readAsString()));
  await for (final t in tokens) {
    switch (t) {
      case XmlStartTag(name: 'sms', :final attributes):
        sms.add({...attributes, '_id': '${++id}'});
      case XmlStartTag(name: 'mms', :final attributes):
        current = {...attributes, '_id': '${++id}', 'parts': <Map<String, String>>[], 'addrs': <Map<String, String>>[]};
      case XmlStartTag(name: 'part', :final attributes) when current != null:
        (current['parts'] as List).add({...(Map.of(attributes)..remove('data')), '_id': 'p${++id}'});
      case XmlStartTag(name: 'addr', :final attributes) when current != null:
        (current['addrs'] as List).add(attributes);
      case XmlEndTag(name: 'mms'):
        mms.add(current!);
        current = null;
      default:
    }
  }
  return FakeBridge(sms, mms);
}

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('orbit_engine_test_'));
  tearDown(() async => tmp.delete(recursive: true));

  ReadOptions options() => ReadOptions(attachmentDirectory: p.join(tmp.path, 'att'), ownAddresses: const {'+15550009999'});

  group('Android on-device source', () {
    test('produces the same keys as the XML backup, so both sources dedupe', () async {
      final sink = InMemoryImportSink();
      final engine = ImportEngine(batchSize: 2);
      final xml = await engine.run(SmsBackupRestoreSource(fixturePath('sms_backup_sample.xml')), sink, options: options());
      final bridge = await bridgeFromFixture();
      final device = await engine.run(AndroidDeviceSmsSource(bridge: bridge, pageSize: 2), sink, options: options());
      expect(xml.messagesAdded, 6);
      expect(device.fatalError, isNull);
      expect(device.messagesAdded, 0);
      expect(device.duplicatesSkipped, 6);
    });

    test('imports with paging and copies MMS parts through the bridge', () async {
      final bridge = await bridgeFromFixture();
      final sink = InMemoryImportSink();
      final summary = await ImportEngine().run(AndroidDeviceSmsSource(bridge: bridge, pageSize: 1), sink, options: options());
      expect(summary.messagesAdded, 6);
      expect(sink.threads, hasLength(3));
      // image/png part of the group MMS + image/jpeg part of the sent MMS.
      expect(bridge.copied, hasLength(2));
      expect(summary.attachments, 2);
    });

    test('resumes after the last synced ids and only reads new rows', () async {
      final bridge = await bridgeFromFixture();
      final sink = InMemoryImportSink();
      final first = AndroidDeviceSmsSource(bridge: bridge);
      await ImportEngine().run(first, sink, options: options());
      expect(first.lastSmsId, greaterThan(0));
      expect(first.lastMmsId, greaterThan(0));
      final newId = (first.lastSmsId > first.lastMmsId ? first.lastSmsId : first.lastMmsId) + 1;

      final idle = AndroidDeviceSmsSource(
        bridge: bridge,
        smsAfterId: first.lastSmsId,
        mmsAfterId: first.lastMmsId,
      );
      final nothing = await ImportEngine().run(idle, sink, options: options());
      expect(nothing.messagesAdded + nothing.duplicatesSkipped, 0);

      bridge.sms.add({
        ...bridge.sms.first,
        '_id': '$newId',
        'date': '1900000000000',
        'body': 'brand new',
      });
      final next = AndroidDeviceSmsSource(
        bridge: bridge,
        smsAfterId: idle.lastSmsId,
        mmsAfterId: idle.lastMmsId,
      );
      final update = await ImportEngine().run(next, sink, options: options());
      expect(update.messagesAdded, 1);
      expect(next.lastSmsId, newId);
    });

    test('does not prompt for permission during background syncs', () async {
      final bridge = await bridgeFromFixture()
        ..granted = false;
      final summary = await ImportEngine().run(
        AndroidDeviceSmsSource(bridge: bridge, promptForPermission: false),
        InMemoryImportSink(),
      );
      expect(bridge.permissionRequests, 0);
      expect(summary.fatalError, contains('permission'));
    });

    test('asks for permission and fails clearly when denied', () async {
      final bridge = await bridgeFromFixture()
        ..granted = false;
      final summary = await ImportEngine().run(AndroidDeviceSmsSource(bridge: bridge), InMemoryImportSink());
      expect(bridge.permissionRequests, 1);
      expect(summary.fatalError, contains('permission'));
    });

    test('MethodChannel bridge speaks the documented contract', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(MethodChannelAndroidSmsBridge.channelName);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'status':
            return {'hasPermission': true, 'isDefaultSmsApp': false, 'smsCount': 1, 'mmsCount': 0};
          case 'querySms':
            return (call.arguments as Map)['afterId'] == 0
                ? [
                    {'_id': 7, 'address': '+15551230001', 'date': 1672567200000, 'type': 1, 'body': 'hi', 'read': 1},
                  ]
                : [];
          case 'queryMms':
            return [];
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      final sink = InMemoryImportSink();
      final summary = await ImportEngine().run(AndroidDeviceSmsSource(), sink);
      expect(summary.fatalError, isNull);
      expect(sink.messagesByThread['dm:5551230001']!.single.text, 'hi');
      expect(calls.map((c) => c.method), ['status', 'querySms', 'queryMms']);
      expect(calls[1].arguments, {'afterId': 0, 'limit': 500});
    });
  });

  group('engine', () {
    test('cancellation stops reading, keeps what was read, and reports cancelled', () async {
      final token = CancellationToken();
      final sink = InMemoryImportSink();
      var seen = 0;
      final summary = await ImportEngine().run(
        _CallbackSource(onEach: () {
          if (++seen == 3) token.cancel();
        }),
        sink,
        token: token,
      );
      expect(summary.cancelled, isTrue);
      expect(summary.succeeded, isFalse);
      expect(sink.messageCount, 3);
      expect(sink.lastSummary, same(summary));
    });

    test('applies vCard names to participants without a name', () async {
      final sink = InMemoryImportSink();
      await ImportEngine(contacts: ContactBook.parseVcf('BEGIN:VCARD\nFN:Ben Example\nTEL:+1 555 123 0002\nEND:VCARD\n'))
          .run(SmsBackupRestoreSource(fixturePath('sms_backup_sample.xml')), sink, options: options());
      final group = sink.threads['group:5551230001,5551230002']!;
      expect(group.participants.firstWhere((x) => x.address == '+15551230002').displayName, 'Ben Example');
    });

    test('unexpected errors are reported, not thrown', () async {
      final summary = await ImportEngine().run(_CallbackSource(onEach: () => throw StateError('boom')), InMemoryImportSink());
      expect(summary.fatalError, contains('boom'));
    });
  });
}

class _CallbackSource extends ImportSource {
  _CallbackSource({required this.onEach});

  final void Function() onEach;

  @override
  String get displayName => 'test';

  @override
  Future<void> read(ImportVisitor visitor,
      {required ReadOptions options, required CancellationToken token, ProgressCallback? onProgress}) async {
    const thread = ImportedThread(
      key: 'dm:1',
      participants: [ImportedParticipant(address: '1')],
      isGroup: false,
      service: MessageService.sms,
    );
    await visitor.onThread(thread);
    for (var i = 0; i < 10; i++) {
      token.throwIfCancelled();
      await visitor.onMessage(ImportedMessage(
        key: 'k$i',
        threadKey: thread.key,
        sentAt: DateTime.utc(2020, 1, 1, 0, i),
        isFromMe: i.isEven,
        service: MessageService.sms,
        text: 'm$i',
      ));
      onEach();
    }
  }
}
