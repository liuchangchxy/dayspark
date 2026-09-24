import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/records/record_bus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final recordBusProvider = Provider<RecordBus>(
  (ref) => RecordBus.of(ref.watch(databaseProvider)),
);
