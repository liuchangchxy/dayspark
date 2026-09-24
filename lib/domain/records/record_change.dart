import 'package:dayspark_contracts/dayspark_contracts.dart';

sealed class RecordChange {
  const RecordChange(this.type, this.localId);

  final RecordType type;
  final int localId;
}

final class RecordApplied extends RecordChange {
  const RecordApplied(
    super.type,
    super.localId, {
    required this.previousReference,
  });

  final DateTime? previousReference;
}

final class RecordRemoved extends RecordChange {
  const RecordRemoved(super.type, super.localId, {required this.reminderIds});

  final List<int> reminderIds;
}

final class RecordsBulkChanged extends RecordChange {
  const RecordsBulkChanged(RecordType type, {required this.reason})
    : super(type, 0);

  final String reason;
}
