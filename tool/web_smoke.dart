// Minimal Web startup smoke test: verifies that build/web output exists and
// contains index.html with Flutter root / bootstrap scripts.
import 'dart:io';

void main(List<String> args) {
  String? dir;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dir' && i + 1 < args.length) {
      dir = args[++i];
    }
  }

  if (dir == null) {
    stderr.writeln('Usage: dart run tool/web_smoke.dart --dir <web-build-dir>');
    exit(2);
  }

  final webDir = Directory(dir);
  if (!webDir.existsSync()) {
    stderr.writeln('FAIL: Directory not found: $dir');
    exit(1);
  }

  final indexFile = File('${webDir.path}/index.html');
  if (!indexFile.existsSync()) {
    stderr.writeln('FAIL: index.html missing in $dir');
    exit(1);
  }

  final content = indexFile.readAsStringSync();
  final hasBootstrap = content.contains('flutter_bootstrap.js') ||
      content.contains('main.dart.js') ||
      content.contains('flutter.js');
  if (!hasBootstrap) {
    stderr.writeln('FAIL: index.html does not reference flutter entry script');
    exit(1);
  }

  stdout.writeln('PASS: Web artifact structure verified ($dir)');
}
