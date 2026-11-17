import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class PickedFile {
  const PickedFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

String guessMimeType(String name, Uint8List bytes) {
  final header = bytes.length > 32 ? bytes.sublist(0, 32) : bytes;
  return lookupMimeType(name, headerBytes: header) ??
      'application/octet-stream';
}

/// Opens the system file picker (works on Windows, web, and mobile).
Future<PickedFile?> pickFile({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  final files = await FilePicker.pickFiles(
    type: type,
    allowedExtensions: allowedExtensions,
  );
  if (files.isEmpty) return null;
  final file = files.first;
  final bytes = await file.readAsBytes();
  return PickedFile(
    bytes: bytes,
    name: file.name,
    mimeType: guessMimeType(file.name, bytes),
  );
}

/// Takes a photo with the camera (Android and iOS only).
Future<PickedFile?> takePhoto() async {
  final shot = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 2048,
    imageQuality: 85,
  );
  if (shot == null) return null;
  final bytes = await shot.readAsBytes();
  return PickedFile(
    bytes: bytes,
    name: shot.name,
    mimeType: shot.mimeType ?? guessMimeType(shot.name, bytes),
  );
}
