import 'dart:io';

import 'package:flutter/foundation.dart';

/// Web-safe platform predicates. `dart:io`'s `Platform.*` throws
/// unconditionally in dart2js, so every read must short-circuit on `kIsWeb`.
/// Only file in `lib/` allowed to mention `Platform.*` — guard:
/// `test/architecture/web_platform_guard_test.dart`.
bool get isAndroid => !kIsWeb && Platform.isAndroid;

bool get isIOS => !kIsWeb && Platform.isIOS;

bool get isNativeMobile => isAndroid || isIOS;
