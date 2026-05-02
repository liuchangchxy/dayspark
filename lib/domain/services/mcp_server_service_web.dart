import 'package:dayspark/data/local/database/app_database.dart';

class McpServerService {
  // ignore: unused_field
  final AppDatabase _db;

  McpServerService(this._db);

  bool get isRunning => false;

  Future<void> start({String host = 'localhost', int port = 3000}) async {}

  Future<void> stop() async {}
}
