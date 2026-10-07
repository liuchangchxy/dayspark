import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dayspark/data/local/database/app_database.dart';

typedef ToggleTodoFunction =
    Future<void> Function({
      required int id,
      required bool isCompleted,
      String? occurrenceId,
    });

/// Execution outcome for a [WidgetCommand].
enum CommandExecutionResult {
  /// Command successfully resulted in state mutation.
  success,

  /// Target was already in the desired completed state (no-op, safe to ack).
  alreadyApplied,

  /// Command is structurally or semantically invalid and can never succeed (safe to discard/ack).
  terminalInvalid,

  /// Transient failure occurred; command must remain in storage for next retry.
  retryable,
}

/// Typed versioned command originating from native widgets.
///
/// Ruling O: Independent command contract stored under `widget_command_<commandId>`
/// in shared storage, fully decoupled from `widget_snapshot`.
class WidgetCommand {
  const WidgetCommand({
    this.version = 1,
    required this.commandId,
    required this.action,
    required this.target,
    required this.todoId,
    this.todoSyncId,
    this.occurrenceId,
    this.sourceAllocationId,
    required this.at,
  });

  final int version;
  final String commandId;
  final String action;
  final String target; // 'todo' | 'taskInstance'
  final int todoId;
  final String? todoSyncId;
  final String? occurrenceId;
  final String? sourceAllocationId;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'version': version,
    'commandId': commandId,
    'action': action,
    'target': target,
    'todoId': todoId,
    'todoSyncId': todoSyncId,
    'occurrenceId': occurrenceId,
    'sourceAllocationId': sourceAllocationId,
    'at': at.toUtc().toIso8601String(),
  };

  factory WidgetCommand.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final commandId = json['commandId'];
    final action = json['action'];
    final target = json['target'];
    final todoId = json['todoId'];
    final atStr = json['at'];

    if (version is! int ||
        commandId is! String ||
        action is! String ||
        target is! String ||
        todoId is! int ||
        atStr is! String) {
      throw FormatException('Malformed WidgetCommand: $json');
    }

    final at = DateTime.tryParse(atStr) ?? DateTime.now();

    return WidgetCommand(
      version: version,
      commandId: commandId,
      action: action,
      target: target,
      todoId: todoId,
      todoSyncId: json['todoSyncId'] as String?,
      occurrenceId: json['occurrenceId'] as String?,
      sourceAllocationId: json['sourceAllocationId'] as String?,
      at: at,
    );
  }
}

/// Raw entry retrieved from the command transport.
class WidgetCommandEntry {
  const WidgetCommandEntry({required this.commandId, required this.rawJson});

  final String commandId;
  final String rawJson;
}

/// Transport abstraction for accessing the independent command queue.
abstract interface class WidgetCommandTransport {
  /// Fetches all pending native commands.
  Future<List<WidgetCommandEntry>> fetchPendingCommands();

  /// Acknowledges and physically deletes the specific command key.
  Future<void> ackCommand(String commandId);
}

/// Production implementation communicating with platform SharedPreferences / UserDefaults.
class PlatformWidgetCommandTransport implements WidgetCommandTransport {
  const PlatformWidgetCommandTransport();

  static const MethodChannel _channel = MethodChannel(
    'com.dayspark.app/widget_commands',
  );

  @override
  Future<List<WidgetCommandEntry>> fetchPendingCommands() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getPendingCommands',
      );
      if (result == null) return const [];
      final entries = <WidgetCommandEntry>[];
      for (final item in result) {
        if (item is Map) {
          final id = item['commandId'];
          final raw = item['raw'];
          if (id is String && raw is String) {
            entries.add(WidgetCommandEntry(commandId: id, rawJson: raw));
          }
        }
      }
      return entries;
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      debugPrint('widget_commands: fetch error: $e');
      return const [];
    }
  }

  @override
  Future<void> ackCommand(String commandId) async {
    try {
      await _channel.invokeMethod<bool>('ackCommand', {'commandId': commandId});
    } on MissingPluginException {
      // Ignored in test/unsupported environments.
    } on PlatformException catch (e) {
      debugPrint('widget_commands: ack error ($commandId): $e');
    }
  }
}

/// In-memory transport for unit testing and vertical integration tests.
class InMemoryWidgetCommandTransport implements WidgetCommandTransport {
  InMemoryWidgetCommandTransport([Map<String, String>? initial])
    : _storage = Map<String, String>.from(initial ?? const {});

  final Map<String, String> _storage;

  void pushCommand(WidgetCommand command) {
    _storage[command.commandId] = jsonEncode(command.toJson());
  }

  void pushRaw(String commandId, String rawJson) {
    _storage[commandId] = rawJson;
  }

  Map<String, String> get storage => Map.unmodifiable(_storage);

  @override
  Future<List<WidgetCommandEntry>> fetchPendingCommands() async {
    return _storage.entries
        .map((e) => WidgetCommandEntry(commandId: e.key, rawJson: e.value))
        .toList();
  }

  @override
  Future<void> ackCommand(String commandId) async {
    _storage.remove(commandId);
  }
}

/// Executes a single [WidgetCommand] with semantic idempotency and fail-closed validation.
Future<CommandExecutionResult> executeWidgetCommand(
  AppDatabase db,
  WidgetCommand command, {
  required ToggleTodoFunction toggleTodo,
}) async {
  // Validate protocol & action
  if (command.version != 1 || command.action != 'complete') {
    debugPrint(
      'widget_command: unsupported version ${command.version} or action ${command.action}',
    );
    return CommandExecutionResult.terminalInvalid;
  }

  try {
    // 1. Resolve target Todo using strict 5-case identity resolver
    final localById = await (db.select(db.todos)
          ..where((t) => t.id.equals(command.todoId) & t.deletedAt.isNull()))
        .getSingleOrNull();

    Todo? stableBySyncId;
    if (command.todoSyncId != null && command.todoSyncId!.isNotEmpty) {
      stableBySyncId = await (db.select(db.todos)
            ..where(
              (t) =>
                  t.syncId.equals(command.todoSyncId!) & t.deletedAt.isNull(),
            ))
          .getSingleOrNull();
    }

    final Todo todo;
    if (localById != null && stableBySyncId != null) {
      if (localById.id == stableBySyncId.id) {
        // Case A: localById + stableBySyncId identify the exact same row -> OK
        todo = localById;
      } else {
        // Case C: both exist but point to different rows -> TERMINAL_INVALID
        debugPrint(
          'widget_command: resolver collision! localById (${localById.id}) != stableBySyncId (${stableBySyncId.id})',
        );
        return CommandExecutionResult.terminalInvalid;
      }
    } else if (localById == null && stableBySyncId != null) {
      // Case B: only stableBySyncId exists -> use stable
      todo = stableBySyncId;
    } else if (localById != null && stableBySyncId == null) {
      // If command specified a non-empty todoSyncId but stableBySyncId was null (or localById.syncId != null && mismatches),
      // or if local row has null syncId while command gave a syncId that doesn't resolve to it -> Case D
      if (command.todoSyncId != null && command.todoSyncId!.isNotEmpty) {
        // Command provided syncId, but local row either doesn't match or doesn't have it -> TERMINAL_INVALID
        debugPrint(
          'widget_command: localById ${localById.id} syncId (${localById.syncId}) does not match command syncId (${command.todoSyncId})',
        );
        return CommandExecutionResult.terminalInvalid;
      } else {
        // Command didn't specify todoSyncId, localById alone is resolved
        todo = localById;
      }
    } else {
      // Case E: neither exists -> TERMINAL_INVALID
      debugPrint(
        'widget_command: target todo ${command.todoId} / ${command.todoSyncId} does not exist',
      );
      return CommandExecutionResult.terminalInvalid;
    }

    // Double check identity consistency
    if (command.todoSyncId != null &&
        command.todoSyncId!.isNotEmpty &&
        todo.syncId != null &&
        todo.syncId!.isNotEmpty &&
        todo.syncId != command.todoSyncId) {
      debugPrint(
        'widget_command: identity mismatch! todo.syncId ${todo.syncId} != command ${command.todoSyncId}',
      );
      return CommandExecutionResult.terminalInvalid;
    }

    // 3. Dispatch based on target
    if (command.target == 'todo') {
      final isRecurring =
          (todo.rrule != null && todo.rrule!.isNotEmpty) ||
          (todo.recurrenceRule != null && todo.recurrenceRule!.isNotEmpty);
      if (isRecurring) {
        debugPrint(
          'widget_command: recurring todo cannot be targeted via target=todo (requires target=taskInstance)',
        );
        return CommandExecutionResult.terminalInvalid; // Strict target rule
      }
      if (todo.status == 'COMPLETED') {
        return CommandExecutionResult.alreadyApplied;
      }
      await toggleTodo(id: todo.id, isCompleted: true, occurrenceId: command.occurrenceId);
      return CommandExecutionResult.success;
    } else if (command.target == 'taskInstance') {
      final occurrenceId = command.occurrenceId;
      if (occurrenceId == null || occurrenceId.isEmpty) {
        debugPrint(
          'widget_command: taskInstance command missing required occurrenceId',
        );
        return CommandExecutionResult.terminalInvalid; // Ruling C: fail closed
      }

      final isRecurring =
          (todo.rrule != null && todo.rrule!.isNotEmpty) ||
          (todo.recurrenceRule != null && todo.recurrenceRule!.isNotEmpty);
      if (!isRecurring) {
        debugPrint(
          'widget_command: taskInstance target specified for non-recurring todo ${todo.id}',
        );
        return CommandExecutionResult.terminalInvalid;
      }

      // Semantic idempotency check
      if (todo.syncId != null && todo.syncId!.isNotEmpty) {
        final state =
            await (db.select(db.taskInstanceStates)..where(
                  (s) =>
                      s.todoSyncId.equals(todo.syncId!) &
                      s.occurrenceId.equals(occurrenceId),
                ))
                .getSingleOrNull();
        if (state != null && state.status.toLowerCase() == 'completed') {
          return CommandExecutionResult.alreadyApplied;
        }
      }

      await toggleTodo(
        id: todo.id,
        isCompleted: true,
        occurrenceId: occurrenceId,
      );
      return CommandExecutionResult.success;
    } else {
      debugPrint('widget_command: unknown target ${command.target}');
      return CommandExecutionResult.terminalInvalid;
    }
  } catch (e) {
    if (e is StateError || e is FormatException) {
      debugPrint('widget_command: terminal domain error: $e');
      return CommandExecutionResult.terminalInvalid;
    }
    debugPrint('widget_command: transient execution failure: $e');
    return CommandExecutionResult.retryable;
  }
}

/// Drains and processes all pending commands from [transport].
Future<void> consumeWidgetCommands({
  required AppDatabase db,
  required WidgetCommandTransport transport,
  required ToggleTodoFunction toggleTodo,
}) async {
  final entries = await transport.fetchPendingCommands();
  if (entries.isEmpty) return;

  final parsedEntries = <({WidgetCommand? command, WidgetCommandEntry entry})>[];
  for (final entry in entries) {
    try {
      final json = jsonDecode(entry.rawJson);
      if (json is Map<String, dynamic>) {
        parsedEntries.add((
          command: WidgetCommand.fromJson(json),
          entry: entry,
        ));
        continue;
      }
    } catch (_) {}
    parsedEntries.add((command: null, entry: entry));
  }

  // Deterministic order: by timestamp asc, then by commandId
  parsedEntries.sort((a, b) {
    if (a.command == null && b.command == null) return 0;
    if (a.command == null) return -1;
    if (b.command == null) return 1;
    final timeCompare = a.command!.at.compareTo(b.command!.at);
    if (timeCompare != 0) return timeCompare;
    return a.command!.commandId.compareTo(b.command!.commandId);
  });

  for (final item in parsedEntries) {
    final command = item.command;
    final entry = item.entry;

    if (command == null) {
      // Corrupt/malformed JSON: terminal invalid, ack and discard
      await transport.ackCommand(entry.commandId);
      continue;
    }

    if (entry.commandId != command.commandId) {
      // Storage key does not match payload commandId: ack storage key and discard (zero domain mutation)
      debugPrint(
        'widget_command: storage key ${entry.commandId} does not match payload commandId ${command.commandId}, discarding',
      );
      await transport.ackCommand(entry.commandId);
      continue;
    }

    final result = await executeWidgetCommand(
      db,
      command,
      toggleTodo: toggleTodo,
    );

    switch (result) {
      case CommandExecutionResult.success:
      case CommandExecutionResult.alreadyApplied:
      case CommandExecutionResult.terminalInvalid:
        await transport.ackCommand(entry.commandId);
      case CommandExecutionResult.retryable:
        // Do not ack; leave in storage for next retry
        break;
    }
  }
}
