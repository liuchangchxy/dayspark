import 'dart:io';

Future<String> readFileNative(String path) => File(path).readAsString();

bool get isDesktopPlatform => !bool.fromEnvironment('dart.library.html');
