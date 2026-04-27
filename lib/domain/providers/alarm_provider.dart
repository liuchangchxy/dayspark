import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/domain/services/alarm_service.dart';

/// AlarmService singleton provider.
final alarmServiceProvider = Provider<AlarmService>((ref) {
  final service = AlarmService();
  service.init();
  return service;
});
