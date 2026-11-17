import 'package:flutter/foundation.dart';

/// What the current platform can do, so the UI can degrade gracefully.
class PlatformCaps {
  static bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// `video_player` has no Windows or Linux implementation.
  static bool get inlineVideo =>
      kIsWeb ||
      _mobile ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Camera capture through `image_picker` is only available on phones.
  static bool get camera => _mobile;
}
