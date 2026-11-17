import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/gif_service.dart';
import '../services/sticker_pack.dart';
import '../theme/orbit_theme.dart';
import 'net_image.dart';

/// What the user chose in the GIF sheet.
sealed class GifChoice {
  const GifChoice();
}

class GifSearchChoice extends GifChoice {
  const GifSearchChoice(this.gif);
  final GifResult gif;
}

class GifFileChoice extends GifChoice {
  const GifFileChoice();
}

Future<GifChoice?> showGifPicker(BuildContext context, GifService gifs) {
  return showModalBottomSheet<GifChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OrbitColors.panel,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.75,
      child: _GifSheet(gifs: gifs),
    ),
  );
}

class _GifSheet extends StatefulWidget {
  const _GifSheet({required this.gifs});

  final GifService gifs;

  @override
  State<_GifSheet> createState() => _GifSheetState();
}

class _GifSheetState extends State<_GifSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<GifResult> _results = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.gifs.isEnabled) _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.gifs.search(q);
      if (mounted && id == _request) setState(() => _results = results);
    } catch (_) {
      if (mounted && id == _request) {
        setState(() => _error = 'Could not load GIFs. Check your connection.');
      }
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileButton = OutlinedButton.icon(
      onPressed: () => Navigator.pop(context, const GifFileChoice()),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      icon: const Icon(Icons.folder_open_rounded),
      label: const Text('Send a GIF file'),
    );

    if (!widget.gifs.isEnabled) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.gif_box_outlined, size: 40, color: OrbitColors.mute),
            const SizedBox(height: 12),
            Text('GIF search is off',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'To search GIFs, run Orbit with a Giphy API key:\n'
              'flutter run --dart-define=GIPHY_API_KEY=your_key\n\n'
              'You can still send a GIF file from this device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: OrbitColors.soft, height: 1.45),
            ),
            const SizedBox(height: 20),
            fileButton,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search GIFs',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce =
                  Timer(const Duration(milliseconds: 350), () => _load(v));
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: OrbitColors.soft)))
                : _loading && _results.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final gif = _results[index];
                          return Semantics(
                            button: true,
                            label: gif.title.isEmpty ? 'GIF' : gif.title,
                            excludeSemantics: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  Navigator.pop(context, GifSearchChoice(gif)),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: NetImage(gif.previewUrl),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Powered by GIPHY',
                  style: TextStyle(fontSize: 11, color: OrbitColors.mute)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, const GifFileChoice()),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Send a GIF file'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<Sticker?> showStickerPicker(BuildContext context) {
  return showModalBottomSheet<Sticker>(
    context: context,
    backgroundColor: OrbitColors.panel,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stickers', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final sticker in stickerPack)
                  Tooltip(
                    message: sticker.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, sticker),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: SvgPicture.asset(
                          sticker.asset,
                          semanticsLabel: '${sticker.label} sticker',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
