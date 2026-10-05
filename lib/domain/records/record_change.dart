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
  });

  @override
  final RecordType type;
  final DateTime? previousReference;
}

final class RecordRemoved extends RecordChange {
  const RecordRemoved(this.type, super.localId, {required this.reminderIds});

  @override
  final RecordType type;
  final List<int> reminderIds;
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
