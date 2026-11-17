import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;
import 'package:record/record.dart';

import 'temp_path_web.dart' if (dart.library.io) 'temp_path_io.dart';

class RecordedAudio {
  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.duration,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final Duration duration;
}

/// Records voice messages, choosing the first encoder the platform supports.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;
  _Format? _format;

  static const _formats = [
    _Format(AudioEncoder.aacLc, 'm4a', 'audio/mp4'),
    _Format(AudioEncoder.opus, 'webm', 'audio/webm'),
    _Format(AudioEncoder.wav, 'wav', 'audio/wav'),
  ];

  /// Starts recording. Returns `false` if permission was denied or no
  /// supported encoder exists.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    _Format? format;
    for (final f in _formats) {
      if (await _recorder.isEncoderSupported(f.encoder)) {
        format = f;
        break;
      }
    }
    if (format == null) return false;
    _format = format;
    final name = 'orbit_voice_${DateTime.now().millisecondsSinceEpoch}.${format.ext}';
    await _recorder.start(
      RecordConfig(encoder: format.encoder, numChannels: 1, bitRate: 64000),
      path: tempFilePath(name),
    );
    _startedAt = DateTime.now();
    return true;
  }

  Future<RecordedAudio?> stop() async {
    final path = await _recorder.stop();
    final format = _format;
    final started = _startedAt;
    _startedAt = null;
    if (path == null || format == null || started == null) return null;
    final bytes = await XFile(path).readAsBytes();
    return RecordedAudio(
      bytes: bytes,
      mimeType: format.mimeType,
      fileName: 'voice_message.${format.ext}',
      duration: DateTime.now().difference(started),
    );
  }

  Future<void> cancel() async {
    _startedAt = null;
    await _recorder.cancel();
  }

  Future<void> dispose() => _recorder.dispose();
}

class _Format {
  const _Format(this.encoder, this.ext, this.mimeType);

  final AudioEncoder encoder;
  final String ext;
  final String mimeType;
}
