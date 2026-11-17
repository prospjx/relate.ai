import 'package:flutter/widgets.dart';

/// Importing reads local backup files and SQLite databases, which the web
/// build can't do.
const importSupported = false;

Widget buildImportScreen(BuildContext context) =>
    throw UnsupportedError('Importing chats is not available on the web');
