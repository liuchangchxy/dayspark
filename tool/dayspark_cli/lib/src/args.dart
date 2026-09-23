class UsageException implements Exception {
  UsageException(this.message);

  final String message;

  @override
  String toString() => 'UsageException: $message';
}

class ParsedArgs {
  ParsedArgs(this.path, this.options, this.positionals);

  final List<String> path;
  final Map<String, String> options;
  final List<String> positionals;
}

const Set<String> knownFlags = <String>{
  'server',
  'email',
  'filter',
  'status',
  'limit',
  'due',
  'priority',
  'from',
  'to',
  'title',
  'start',
  'end',
  'description',
  'location',
};

// Grammar: leading words build the command path (group + subcommand, e.g.
// `task list`); every other bare word is a positional. All options take a
// value — the CLI has no boolean flags, so `--x` at the end is a usage error.
ParsedArgs parseArgs(List<String> args) {
  final path = <String>[];
  final options = <String, String>{};
  final positionals = <String>[];
  var i = 0;
  while (i < args.length) {
    final token = args[i];
    if (token.startsWith('--')) {
      final name = token.substring(2);
      if (!knownFlags.contains(name)) {
        throw UsageException('unknown option $token');
      }
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        throw UsageException('missing value for $token');
      }
      options[name] = args[i + 1];
      i += 2;
      continue;
    }
    final isGroup =
        path.isNotEmpty && (path[0] == 'task' || path[0] == 'event');
    if (path.isEmpty || (isGroup && path.length < 2)) {
      path.add(token);
    } else {
      positionals.add(token);
    }
    i++;
  }
  return ParsedArgs(path, options, positionals);
}
