import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../services/platform_caps.dart';
import '../services/sticker_pack.dart';
import '../theme/orbit_theme.dart';
import '../util/formatting.dart';
import 'net_image.dart';

const _maxMediaWidth = 260.0;
const _maxMediaHeight = 320.0;

Future<void> openExternally(BuildContext context, String? url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = url == null ? null : Uri.tryParse(url);
  final ok = uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not open this file.')));
  }
}

Size _fit(Attachment a) {
  final w = a.width?.toDouble();
  final h = a.height?.toDouble();
  if (w == null || h == null || w <= 0 || h <= 0) {
    return const Size(_maxMediaWidth, 200);
  }
  final scale = [_maxMediaWidth / w, _maxMediaHeight / h, 1.0]
      .reduce((a, b) => a < b ? a : b);
  final width = (w * scale).clamp(120.0, _maxMediaWidth);
  return Size(width, h * (width / w));
}

/// Renders one attachment inside a message bubble.
class AttachmentView extends StatelessWidget {
  const AttachmentView({
    super.key,
    required this.attachment,
    this.mine = false,
  });

  final Attachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    switch (attachment.kind) {
      case AttachmentKind.image:
      case AttachmentKind.gif:
        return _ImageAttachment(attachment: attachment);
      case AttachmentKind.sticker:
        return StickerView(stickerId: attachment.stickerId);
      case AttachmentKind.video:
        return PlatformCaps.inlineVideo
            ? _InlineVideo(attachment: attachment, mine: mine)
            : _FileTile(
                attachment: attachment,
                icon: Icons.movie_outlined,
                fallbackName: 'Video',
                actionLabel: 'Open video',
                mine: mine,
              );
      case AttachmentKind.audio:
        return AudioMessagePlayer(attachment: attachment, mine: mine);
      case AttachmentKind.document:
        return _FileTile(
          attachment: attachment,
          icon: Icons.description_outlined,
          fallbackName: 'Document',
          actionLabel: 'Open',
          mine: mine,
        );
    }
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final url = attachment.url;
    if (url == null) return const SizedBox.shrink();
    final size = _fit(attachment);
    final isGif = attachment.kind == AttachmentKind.gif;
    return Semantics(
      button: true,
      label: isGif ? 'GIF, open full screen' : 'Photo, open full screen',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _ImageViewer(url: url, name: attachment.name),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              NetImage(url, width: size.width, height: size.height),
              if (isGif)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, this.name});

  final String url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        shape: const Border(),
        title: Text(
          name ?? 'Photo',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Open in browser',
            onPressed: () => openExternally(context, url),
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: NetImage(url, fit: BoxFit.contain)),
      ),
    );
  }
}

class StickerView extends StatelessWidget {
  const StickerView({super.key, required this.stickerId, this.size = 140});

  final String? stickerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final sticker = stickerById(stickerId);
    if (sticker == null) {
      return Text(
        'Sticker',
        style: TextStyle(
          color: palette.secondaryInk,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return SvgPicture.asset(
      sticker.asset,
      width: size,
      height: size,
      semanticsLabel: '${sticker.label} sticker',
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.attachment,
    required this.icon,
    required this.fallbackName,
    required this.actionLabel,
    this.mine = false,
  });

  final Attachment attachment;
  final IconData icon;
  final String fallbackName;
  final String actionLabel;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final fg = mine ? palette.onOutgoingBubble : palette.onIncomingBubble;
    final secondary = mine
        ? palette.onOutgoingBubble.withValues(alpha: 0.78)
        : palette.secondaryInk;
    final fill = mine
        ? Colors.white.withValues(alpha: 0.16)
        : palette.ink.withValues(alpha: 0.06);

    final details = [
      formatBytes(attachment.sizeBytes),
      if (attachment.mimeType != null)
        attachment.mimeType!.split('/').last.toUpperCase(),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Semantics(
      button: true,
      label: '$actionLabel ${attachment.name ?? fallbackName}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openExternally(context, attachment.url),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56, maxWidth: 280),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: fg),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.name ?? fallbackName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: TextStyle(
                          fontSize: 12,
                          color: secondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded, size: 17, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({required this.attachment, this.mine = false});

  final Attachment attachment;
  final bool mine;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.attachment.url;
    if (url == null) return;
    var controller = _controller;
    if (controller == null) {
      controller = VideoPlayerController.networkUrl(Uri.parse(url));
      setState(() => _controller = controller);
      try {
        await controller.initialize();
        controller.addListener(() {
          if (mounted) setState(() {});
        });
      } catch (_) {
        if (mounted) setState(() => _failed = true);
        return;
      }
    }
    controller.value.isPlaying
        ? await controller.pause()
        : await controller.play();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _FileTile(
        attachment: widget.attachment,
        icon: Icons.movie_outlined,
        fallbackName: 'Video',
        actionLabel: 'Open video',
        mine: widget.mine,
      );
    }
    final palette = MessengerPalette.of(context);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final playing = ready && controller.value.isPlaying;
    final size = ready
        ? _fit(Attachment(
            kind: AttachmentKind.video,
            width: controller.value.size.width.round(),
            height: controller.value.size.height.round(),
          ))
        : _fit(widget.attachment);
    return Semantics(
      button: true,
      label: playing ? 'Pause video' : 'Play video',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size.width,
            height: size.height,
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (ready)
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                if (controller != null && !ready)
                  const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                if (!playing && (ready || controller == null))
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                if (ready)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: palette.accent,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Play and pause control for voice messages and audio files.
class AudioMessagePlayer extends StatefulWidget {
  const AudioMessagePlayer({
    super.key,
    required this.attachment,
    this.mine = false,
  });

  final Attachment attachment;
  final bool mine;

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subs = [];
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.attachment.durationMs;
    if (ms != null) _duration = Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _subs
      ..add(player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _state = s);
      }))
      ..add(player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }))
      ..add(player.onDurationChanged.listen((d) {
        if (mounted && d > Duration.zero) setState(() => _duration = d);
      }))
      ..add(player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      }));
    return _player = player;
  }

  Future<void> _toggle() async {
    final url = widget.attachment.url;
    if (url == null) return;
    final player = _ensurePlayer();
    try {
      if (_state == PlayerState.playing) {
        await player.pause();
      } else if (_state == PlayerState.paused) {
        await player.resume();
      } else {
        await player
            .play(UrlSource(url, mimeType: widget.attachment.mimeType));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    final fg =
        widget.mine ? palette.onOutgoingBubble : palette.onIncomingBubble;
    final secondary = widget.mine
        ? palette.onOutgoingBubble.withValues(alpha: 0.78)
        : palette.secondaryInk;
    final buttonFill = widget.mine
        ? Colors.white.withValues(alpha: 0.16)
        : palette.ink.withValues(alpha: 0.06);
    final trackColor = widget.mine
        ? Colors.white.withValues(alpha: 0.25)
        : palette.ink.withValues(alpha: 0.12);
    final progressColor = widget.mine ? Colors.white : palette.accent;

    final playing = _state == PlayerState.playing;
    final total = _duration ?? Duration.zero;
    final progress = total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          IconButton(
            tooltip: playing ? 'Pause voice message' : 'Play voice message',
            onPressed: _failed
                ? () => openExternally(context, widget.attachment.url)
                : _toggle,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: buttonFill,
              foregroundColor: fg,
            ),
            icon: Icon(
              _failed
                  ? Icons.open_in_new_rounded
                  : playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: trackColor,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _failed
                      ? 'Cannot play here. Open instead.'
                      : playing || _position > Duration.zero
                          ? formatDuration(_position)
                          : (total > Duration.zero
                              ? formatDuration(total)
                              : 'Voice message'),
                  style: TextStyle(
                    fontSize: 12,
                    color: secondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
