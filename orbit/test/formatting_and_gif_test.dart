import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbit/models/models.dart';
import 'package:orbit/services/gif_service.dart';
import 'package:orbit/services/sticker_pack.dart';
import 'package:orbit/util/formatting.dart';

Message _m(String id, DateTime at, String sender,
        {MessageKind kind = MessageKind.text}) =>
    Message(
      id: id,
      conversationId: 'c',
      kind: kind,
      sentAt: at,
      senderId: sender,
      text: id,
    );

void main() {
  group('buildTimeline', () {
    test('adds a separator per day and marks sender runs', () {
      final d1 = DateTime(2026, 5, 1, 9);
      final d2 = DateTime(2026, 5, 2, 9);
      final entries = buildTimeline([
        _m('c', d2, 'a'),
        _m('a', d1, 'a'),
        _m('b', d1.add(const Duration(minutes: 1)), 'a'),
        _m('d', d2.add(const Duration(minutes: 1)), 'b'),
      ]);
      final shape = entries
          .map((e) => switch (e) {
                DaySeparatorEntry(:final day) => 'day:${day.day}',
                MessageEntry(:final message, :final showSender) =>
                  '${message.id}${showSender ? '*' : ''}',
              })
          .toList();
      expect(shape, ['day:1', 'a*', 'b', 'day:2', 'c*', 'd*']);
    });

    test('system messages reset sender runs', () {
      final t = DateTime(2026, 5, 1, 9);
      final entries = buildTimeline([
        _m('a', t, 'x'),
        _m('s', t.add(const Duration(minutes: 1)), 'x',
            kind: MessageKind.system),
        _m('b', t.add(const Duration(minutes: 2)), 'x'),
      ]).whereType<MessageEntry>().toList();
      expect(entries.map((e) => e.showSender), [true, false, true]);
    });
  });

  test('day separator labels', () {
    final now = DateTime(2026, 11, 17, 15);
    expect(daySeparatorLabel(DateTime(2026, 11, 17, 1), now), 'Today');
    expect(daySeparatorLabel(DateTime(2026, 11, 16, 23), now), 'Yesterday');
    expect(daySeparatorLabel(DateTime(2026, 11, 13), now), 'Friday');
    expect(daySeparatorLabel(DateTime(2026, 2, 3), now), 'February 3');
    expect(daySeparatorLabel(DateTime(2024, 2, 3), now), 'February 3, 2024');
  });

  test('presence labels', () {
    final now = DateTime(2026, 11, 17, 15);
    UserProfile p({required bool online, DateTime? seen}) => UserProfile(
        uid: 'u', displayName: 'U', online: online, lastSeen: seen);
    expect(presenceLabel(p(online: true, seen: now), now), 'Online');
    expect(
      presenceLabel(
          p(online: false, seen: now.subtract(const Duration(minutes: 5))),
          now),
      'Last seen 5 min ago',
    );
    expect(presenceLabel(p(online: false), now), 'Offline');
  });

  test('formatBytes and formatDuration', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatDuration(const Duration(seconds: 75)), '1:15');
  });

  group('GifService', () {
    test('is disabled without a key', () async {
      final gifs = GifService(apiKey: '');
      expect(gifs.isEnabled, isFalse);
      expect(() => gifs.search('cats'), throwsStateError);
    });

    test('parses Giphy results', () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'abc',
                'title': 'Cat',
                'images': {
                  'fixed_width': {'url': 'https://g/preview.gif'},
                  'downsized': {
                    'url': 'https://g/full.gif',
                    'width': '480',
                    'height': '270',
                  },
                },
              },
              {'id': 'broken'},
            ],
          }),
          200,
        );
      });
      final gifs = GifService(apiKey: 'k', client: client);
      final results = await gifs.search('cat');
      expect(requested.path, '/v1/gifs/search');
      expect(requested.queryParameters['q'], 'cat');
      expect(results, hasLength(1));
      expect(results.single.url, 'https://g/full.gif');
      expect(results.single.width, 480);
    });
  });

  test('sticker pack ids resolve', () {
    expect(stickerPack, isNotEmpty);
    for (final s in stickerPack) {
      expect(stickerById(s.id), same(s));
      expect(s.asset, startsWith('assets/stickers/'));
    }
    expect(stickerById('nope'), isNull);
  });
}
