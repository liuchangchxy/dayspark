import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dayspark_cli/src/api.dart';
import 'package:dayspark_cli/src/args.dart';

const int exitOk = 0;
const int exitToolError = 1;
const int exitUsageOrAuth = 2;

const String usage = '''
usage: dayspark <command> [options]

commands:
  login --server URL --email EMAIL   sign in and store credentials
  logout                             remove stored credentials
  status                             show session identity
  task list [--filter F] [--status S] [--limit N]
  task add TITLE [--due ISO] [--priority N]
  task done ID
  task trash ID
  event list [--from ISO] [--to ISO]
  event add --title T --start ISO --end ISO [--description D] [--location L]
  help

options: --server --email --filter --status --limit --due --priority
         --from --to --title --start --end --description --location

exit codes: 0 ok, 1 tool/server error, 2 usage or auth error
''';

class _Ctx {
  _Ctx({
    required this.out,
    required this.err,
    required this.environment,
    required this.readPassword,
    required this.httpClient,
  });

  final StringSink out;
  final StringSink err;
  final Map<String, String> environment;
  final Future<String?> Function() readPassword;
  final HttpClient httpClient;
}

Future<String?> _promptPassword(StringSink err) async {
  err.write('Password: ');
  if (err is IOSink) await err.flush();
  // No-echo: Stdin has no per-read echo flag, so toggle echoMode around the
  // read and restore the previous value. Non-tty stdin (pipes, CI) rejects
  // echoMode writes — fall back to a plain read there.
  bool? previousEcho;
  try {
    previousEcho = stdin.echoMode;
    stdin.echoMode = false;
  } on StdinException {
    previousEcho = null;
  }
  try {
    return stdin.readLineSync();
  } on StdinException {
    return null;
  } finally {
    if (previousEcho != null) {
      try {
        stdin.echoMode = previousEcho;
      } on StdinException {
        // Best effort — the terminal is already gone or not a tty.
      }
    }
  }
}

Future<int> runDayspark(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? environment,
  Future<String?> Function()? readPassword,
}) async {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;
  final env = environment ?? Platform.environment;
  final httpClient = HttpClient();
  final ctx = _Ctx(
    out: outSink,
    err: errSink,
    environment: env,
    readPassword: readPassword ?? () => _promptPassword(errSink),
    httpClient: httpClient,
  );
  try {
    if (args.isEmpty) throw UsageException('command required');
    if (args.first == 'help' || args.first == '--help' || args.first == '-h') {
      outSink.write(usage);
      return exitOk;
    }
    final parsed = parseArgs(args);
    await _dispatch(ctx, parsed);
    return exitOk;
  } on UsageException catch (e) {
    errSink.writeln('dayspark: ${e.message}');
    errSink.write(usage);
    return exitUsageOrAuth;
  } on AuthFailure catch (e) {
    errSink.writeln('dayspark: ${e.message}');
    return exitUsageOrAuth;
  } on ToolFailure catch (e) {
    errSink.writeln('dayspark: ${e.message}');
    return exitToolError;
  } finally {
    httpClient.close(force: true);
    if (outSink is IOSink) await outSink.flush();
    if (errSink is IOSink) await errSink.flush();
  }
}

Future<void> _dispatch(_Ctx ctx, ParsedArgs parsed) async {
  if (parsed.path.isEmpty) throw UsageException('command required');
  final group = parsed.path.first;
  final sub = parsed.path.length > 1 ? parsed.path[1] : '';
  switch (group) {
    case 'login':
      await _login(ctx, parsed);
    case 'logout':
      await _logout(ctx);
    case 'status':
      await _status(ctx);
    case 'task':
      await _task(ctx, parsed, sub);
    case 'event':
      await _event(ctx, parsed, sub);
    default:
      throw UsageException('unknown command: $group');
  }
}

Future<Api> _api(_Ctx ctx) async {
  final credentials =
      await loadCredentials(ctx.environment) ??
      (throw AuthFailure('not logged in — run dayspark login'));
  return Api(
    server: Api.normalizeServer(credentials.server),
    httpClient: ctx.httpClient,
    credentials: credentials,
    onRotated: (Credentials updated) => saveCredentials(updated, ctx.environment),
  );
}

String _require(ParsedArgs parsed, String flag) {
  final value = parsed.options[flag];
  if (value == null || value.isEmpty) throw UsageException('--$flag is required');
  return value;
}

int _optionalInt(ParsedArgs parsed, String flag) {
  final value = parsed.options[flag];
  if (value == null) throw UsageException('--$flag is required');
  final parsedInt = int.tryParse(value);
  if (parsedInt == null) throw UsageException('--$flag must be an integer');
  return parsedInt;
}

Future<void> _login(_Ctx ctx, ParsedArgs parsed) async {
  final server = Api.normalizeServer(_require(parsed, 'server'));
  final email = _require(parsed, 'email');
  final password = await ctx.readPassword();
  if (password == null || password.isEmpty) {
    throw AuthFailure('password required');
  }
  final credentials = await Api.login(
    server: server,
    email: email,
    password: password,
    httpClient: ctx.httpClient,
  );
  await saveCredentials(credentials, ctx.environment);
  ctx.out.writeln('logged in: ${credentials.userId} @ ${credentials.server}');
}

Future<void> _logout(_Ctx ctx) async {
  await deleteCredentials(ctx.environment);
  ctx.out.writeln('logged out');
}

Future<void> _status(_Ctx ctx) async {
  final api = await _api(ctx);
  final decoded = jsonDecode((await api.me()).body) as Map<String, dynamic>;
  ctx.out.writeln('server\t${api.server}');
  ctx.out.writeln('user\t${decoded['userId']}');
}

String _toolFailureMessage(Map<String, dynamic> payload) {
  final message = payload['message'];
  if (message is String && message.isNotEmpty) return message;
  final code = payload['code'];
  if (code is String) return 'tool failed ($code)';
  return 'tool failed';
}

Future<ToolResult> _call(_Ctx ctx, String name, Map<String, Object?> args) async {
  final api = await _api(ctx);
  final result = await api.toolsCall(name, args);
  if (result.isError) throw ToolFailure(_toolFailureMessage(result.payload));
  return result;
}

String _s(Object? value) => value == null ? '-' : value.toString();

void _printTasks(StringSink out, List<Object?> tasks) {
  if (tasks.isEmpty) {
    out.writeln('(no tasks)');
    return;
  }
  final rows = tasks.cast<Map<String, dynamic>>();
  final statusWidth = _width(rows, 'STATUS', (t) => _s(t['status']));
  final dueWidth = _width(rows, 'DUE', (t) => _s(t['due']));
  final idWidth = _width(rows, 'ID', (t) => _s(t['task_id']));
  out.writeln(
    '${'STATUS'.padRight(statusWidth)}  ${'DUE'.padRight(dueWidth)}  '
    '${'ID'.padRight(idWidth)}  TITLE',
  );
  for (final t in rows) {
    out.writeln(
      '${_s(t['status']).padRight(statusWidth)}  '
      '${_s(t['due']).padRight(dueWidth)}  '
      '${_s(t['task_id']).padRight(idWidth)}  ${_s(t['title'])}',
    );
  }
}

int _width(List<Map<String, dynamic>> rows, String header, String Function(Map<String, dynamic>) pick) {
  var width = header.length;
  for (final row in rows) {
    width = pick(row).length > width ? pick(row).length : width;
  }
  return width;
}

void _printEvents(StringSink out, List<Object?> events) {
  if (events.isEmpty) {
    out.writeln('(no events)');
    return;
  }
  final rows = events.cast<Map<String, dynamic>>();
  final startWidth = _width(rows, 'START', (e) => _s(e['start']));
  final idWidth = _width(rows, 'ID', (e) => _s(e['event_id']));
  out.writeln(
    '${'START'.padRight(startWidth)}  ${'ID'.padRight(idWidth)}  TITLE',
  );
  for (final e in rows) {
    out.writeln(
      '${_s(e['start']).padRight(startWidth)}  '
      '${_s(e['event_id']).padRight(idWidth)}  ${_s(e['title'])}',
    );
  }
}

Future<void> _task(_Ctx ctx, ParsedArgs parsed, String sub) async {
  switch (sub) {
    case 'list':
      final args = <String, Object?>{};
      final filter = parsed.options['filter'];
      if (filter != null) args['filter'] = filter;
      final status = parsed.options['status'];
      if (status != null) args['status'] = status;
      final limit = parsed.options['limit'];
      if (limit != null) {
        final parsedLimit = int.tryParse(limit);
        if (parsedLimit == null) throw UsageException('--limit must be an integer');
        args['limit'] = parsedLimit;
      }
      final result = await _call(ctx, 'list_tasks', args);
      _printTasks(ctx.out, (result.payload['tasks'] as List?) ?? const <Object?>[]);
    case 'add':
      final title = (parsed.options['title'] ?? parsed.positionals.join(' ')).trim();
      if (title.isEmpty) throw UsageException('task add requires a title');
      final args = <String, Object?>{'title': title};
      final due = parsed.options['due'];
      if (due != null) args['due'] = due;
      if (parsed.options.containsKey('priority')) {
        args['priority'] = _optionalInt(parsed, 'priority');
      }
      final result = await _call(ctx, 'create_task', args);
      final task = result.payload['task'] as Map<String, dynamic>?;
      ctx.out.writeln('created ${_s(task?['task_id'])}  ${_s(task?['title'])}');
    case 'done':
      final id = _positionalId(parsed);
      final result = await _call(ctx, 'complete_task', {'task_id': id});
      final task = result.payload['task'] as Map<String, dynamic>?;
      ctx.out.writeln('completed ${_s(task?['task_id'])}');
    case 'trash':
      final id = _positionalId(parsed);
      await _call(ctx, 'trash_task', {'task_id': id});
      ctx.out.writeln('trashed $id');
    default:
      throw UsageException(sub.isEmpty
          ? 'task requires a subcommand: list, add, done, trash'
          : 'unknown task subcommand: $sub');
  }
}

String _positionalId(ParsedArgs parsed) {
  if (parsed.positionals.isEmpty) {
    throw UsageException('a task id is required');
  }
  return parsed.positionals.first;
}

Future<void> _event(_Ctx ctx, ParsedArgs parsed, String sub) async {
  switch (sub) {
    case 'list':
      final args = <String, Object?>{};
      final from = parsed.options['from'];
      if (from != null) args['from'] = from;
      final to = parsed.options['to'];
      if (to != null) args['to'] = to;
      final result = await _call(ctx, 'get_events', args);
      _printEvents(ctx.out, (result.payload['events'] as List?) ?? const <Object?>[]);
    case 'add':
      final title = (parsed.options['title'] ?? parsed.positionals.join(' ')).trim();
      if (title.isEmpty) throw UsageException('event add requires --title');
      final args = <String, Object?>{
        'title': title,
        'start': _require(parsed, 'start'),
        'end': _require(parsed, 'end'),
      };
      final description = parsed.options['description'];
      if (description != null) args['description'] = description;
      final location = parsed.options['location'];
      if (location != null) args['location'] = location;
      final result = await _call(ctx, 'create_event', args);
      final event = result.payload['event'] as Map<String, dynamic>?;
      ctx.out.writeln('created ${_s(event?['event_id'])}  ${_s(event?['title'])}');
    default:
      throw UsageException(sub.isEmpty
          ? 'event requires a subcommand: list, add'
          : 'unknown event subcommand: $sub');
  }
}
