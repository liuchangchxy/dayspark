import 'dart:io';

import 'package:dayspark_cli/dayspark_cli.dart';

Future<void> main(List<String> args) async {
  exit(await runDayspark(args));
}
