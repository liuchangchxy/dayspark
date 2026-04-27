import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/services/mcp_server_service.dart';

final mcpServerProvider = Provider<McpServerService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = McpServerService(db);
  ref.onDispose(() => service.stop());
  return service;
});

final mcpRunningProvider = StateProvider<bool>((ref) => false);

final toggleMcpServerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final isRunning = ref.read(mcpRunningProvider);
    try {
      if (isRunning) {
        await ref.read(mcpServerProvider).stop();
        ref.read(mcpRunningProvider.notifier).state = false;
      } else {
        await ref.read(mcpServerProvider).start();
        ref.read(mcpRunningProvider.notifier).state = true;
      }
    } catch (e) {
      // Ensure state is consistent on failure
      ref.read(mcpRunningProvider.notifier).state = false;
      rethrow;
    }
  };
});
