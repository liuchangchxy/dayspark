import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/mcp_server_service.dart';

final mcpServiceProvider = Provider<McpServerService>((ref) {
  final db = ref.read(databaseProvider);
  final service = McpServerService(db);
  ref.onDispose(() => service.stop());
  return service;
});

final mcpRunningProvider = StateProvider<bool>((ref) => false);
