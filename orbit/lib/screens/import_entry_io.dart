import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/orbit_import_sink.dart';
import '../data/services.dart';
import '../import/ui/import_screen.dart';
import '../state/session.dart';

const importSupported = true;

Widget buildImportScreen(BuildContext context) {
  final services = context.read<OrbitServices>();
  final session = context.read<Session>();
  return ImportScreen(
    sink: OrbitImportSink(
      chats: services.chats,
      importerUid: session.uid,
      importerName: session.displayName,
      readFile: (path) => File(path).readAsBytes(),
      upload: ({
        required conversationId,
        required kind,
        required bytes,
        required fileName,
        required mimeType,
      }) =>
          services.media.uploadChatFile(
        conversationId: conversationId,
        uploaderUid: session.uid,
        kind: kind,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      ),
    ),
  );
}
