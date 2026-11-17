import 'dart:io';

String tempFilePath(String fileName) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName';
