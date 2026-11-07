import 'package:dayspark_contracts/dayspark_contracts.dart';

sealed class RecordChange {
  const RecordChange(this.localId);

  final int localId;
  RecordType? get type => null;
}

final class RecordApplied extends RecordChange {
  const RecordApplied(
    this.type,
    super.localId, {
    required this.previousReference,
    this.reminderIds = const [],
  });

  @override
  final RecordType type;
  final DateTime? previousReference;

  /// Reminder rows whose stored trigger time is authoritative — the parent's
  /// reference did not move them, so the reconciler must not shift them.
  final List<int> reminderIds;
}

final class RecordRemoved extends RecordChange {
  const RecordRemoved(this.type, super.localId, {required this.reminderIds});

  @override
  final RecordType type;
  final List<int> reminderIds;
}

final class RemoteReminderApplied extends RecordChange {
  const RemoteReminderApplied(
    this.type,
    super.localId,
    this.reminderId, {
    required this.changed,
  });

  @override
  final RecordType type;
  final int reminderId;
  final bool changed;
}

final class RecordsBulkChanged extends RecordChange {
  const RecordsBulkChanged(this.type, {required this.reason}) : super(0);

  @override
  final RecordType type;
  final String reason;
}

final class TaskAllocationChanged extends RecordChange {
  const TaskAllocationChanged(super.localId);
}

final class TaskInstanceStateChanged extends RecordChange {
  const TaskInstanceStateChanged(super.localId);
}
