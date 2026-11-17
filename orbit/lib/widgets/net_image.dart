import 'package:flutter/material.dart';

import '../theme/orbit_theme.dart';

/// Network image that falls back to an `<img>` element on web, so Storage
/// and GIF URLs render even without bucket CORS configuration.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.semanticLabel,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      semanticLabel: semanticLabel,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: OrbitColors.raised,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stack) => Container(
        width: width,
        height: height,
        color: OrbitColors.raised,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: OrbitColors.mute),
      ),
    );
  }
}
