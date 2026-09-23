import 'package:dayspark_cli/src/args.dart';
import 'package:test/test.dart';

void main() {
  test('parses login flags and command path', () {
    final parsed = parseArgs(<String>[
      'login',
      '--server',
      'http://localhost:8080',
      '--email',
      'a@b.c',
    ]);
    expect(parsed.path, <String>['login']);
    expect(parsed.options['server'], 'http://localhost:8080');
    expect(parsed.options['email'], 'a@b.c');
    expect(parsed.positionals, isEmpty);
  });

  test('parses two-level task subcommands with positionals', () {
    final parsed = parseArgs(<String>[
      'task',
      'add',
      'Buy',
      'milk',
      '--due',
      '2026-09-24T10:00:00Z',
    ]);
    expect(parsed.path, <String>['task', 'add']);
    expect(parsed.options['due'], '2026-09-24T10:00:00Z');
    expect(parsed.positionals, <String>['Buy', 'milk']);
  });

  test('event list keeps flags and empty positionals', () {
    final parsed = parseArgs(<String>[
      'event',
      'list',
      '--from',
      '2026-09-01T00:00:00Z',
      '--to',
      '2026-09-30T00:00:00Z',
    ]);
    expect(parsed.path, <String>['event', 'list']);
    expect(parsed.options['from'], '2026-09-01T00:00:00Z');
    expect(parsed.options['to'], '2026-09-30T00:00:00Z');
  });

  test('unknown option is a usage error', () {
    expect(
      () => parseArgs(<String>['task', 'list', '--bogus', 'x']),
      throwsA(isA<UsageException>()),
    );
  });

  test('flag without a value is a usage error', () {
    expect(
      () => parseArgs(<String>['login', '--server']),
      throwsA(isA<UsageException>()),
    );
  });

  test('empty args yield an empty path for the dispatcher to reject', () {
    final parsed = parseArgs(<String>[]);
    expect(parsed.path, isEmpty);
    expect(parsed.positionals, isEmpty);
  });

  test('single-level commands never steal positionals into the path', () {
    final parsed = parseArgs(<String>['status', 'stray']);
    expect(parsed.path, <String>['status']);
    expect(parsed.positionals, <String>['stray']);
  });
}
