import 'package:calendar_todo_app/data/local/database/app_database.dart';

class McpServerService {
  // ignore: unused_field
  final AppDatabase _db;
  McpServerService(this._db);

  Future<void> start({int port = 3001}) =>
      throw UnsupportedError('MCP Server not available on web');

  Future<void> stop() async {}
}
