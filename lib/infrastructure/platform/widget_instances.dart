import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:dayspark/core/utils/platform_target.dart';

const MethodChannel _widgetChannel = MethodChannel(
  'com.dayspark.app/widget_commands',
);

/// Whether the launcher currently hosts at least one DaySpark widget.
///
/// Rebuilding the snapshot for zero instances is pure waste on the path that
/// runs right after every write. Non-Android hosts keep the old behaviour: the
/// native side only answers on Android, and anything unexpected means "assume
/// installed" so a widget is never left stale by a faulty probe.
Future<bool> hasInstalledWidgets() async {
  if (homeWidgetPlatform != TargetPlatform.android) return true;
  try {
    final installed = await _widgetChannel.invokeMethod<bool>('hasWidgets');
    return installed ?? true;
  } catch (error) {
    // Any failure means "assume installed": a probe must never be the reason a
    // pinned widget stops updating.
    debugPrint('widget_instances: hasWidgets failed: $error');
    return true;
  }
}
