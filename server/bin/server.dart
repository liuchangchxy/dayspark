import 'package:dayspark_server/server.dart';

Future<void> main(List<String> args) async {
  final app = AppServer(Config.fromEnv());
  await app.serve();
}
