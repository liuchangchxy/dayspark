import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/services/alarm_service.dart';

/// AlarmService singleton provider.
final alarmServiceProvider = Provider<AlarmService>((ref) {
  final service = AlarmService();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    service.init();
  }
  return service;
});
