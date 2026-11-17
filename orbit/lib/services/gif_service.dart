import 'dart:convert';

import 'package:http/http.dart' as http;

class GifResult {
  const GifResult({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.url,
    this.width,
    this.height,
  });

  final String id;
  final String title;
  final String previewUrl;
  final String url;
  final int? width;
  final int? height;
}

/// GIF search via the Giphy API.
///
/// Disabled unless an API key is supplied at build time:
/// `flutter run --dart-define=GIPHY_API_KEY=your_key`.
class GifService {
  GifService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  factory GifService.fromEnvironment() =>
      GifService(apiKey: const String.fromEnvironment('GIPHY_API_KEY'));

  final String apiKey;
  final http.Client _client;

  bool get isEnabled => apiKey.trim().isNotEmpty;

  Future<List<GifResult>> search(String query, {int limit = 24}) {
    final q = query.trim();
    if (q.isEmpty) return trending(limit: limit);
    return _fetch('search', {'q': q, 'limit': '$limit'});
  }

  Future<List<GifResult>> trending({int limit = 24}) =>
      _fetch('trending', {'limit': '$limit'});

  Future<List<GifResult>> _fetch(String endpoint, Map<String, String> params) async {
    if (!isEnabled) throw StateError('GIF search is not configured');
    final uri = Uri.https('api.giphy.com', '/v1/gifs/$endpoint', {
      'api_key': apiKey,
      'rating': 'pg-13',
      ...params,
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('GIF search failed (${response.statusCode})');
    }
    return parseGiphyResponse(response.body);
  }

  static List<GifResult> parseGiphyResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) return const [];
    final results = <GifResult>[];
    for (final item in decoded['data'] as List) {
      if (item is! Map) continue;
      final images = item['images'];
      if (images is! Map) continue;
      final preview = images['fixed_width'] as Map?;
      final full = (images['downsized'] ?? images['original']) as Map?;
      final previewUrl = preview?['url'] as String?;
      final url = full?['url'] as String?;
      if (previewUrl == null || url == null) continue;
      results.add(GifResult(
        id: item['id']?.toString() ?? url,
        title: item['title']?.toString() ?? '',
        previewUrl: previewUrl,
        url: url,
        width: int.tryParse('${full?['width']}'),
        height: int.tryParse('${full?['height']}'),
      ));
    }
    return results;
  }
}
