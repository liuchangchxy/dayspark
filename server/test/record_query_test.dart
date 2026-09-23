import 'dart:convert';

import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:dayspark_server/server.dart';
import 'package:test/test.dart';

DateTime _utc(int y, [int m = 1, int d = 1, int h = 0, int min = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, min, s);

Map<String, dynamic> _event({
  String summary = 'event',
  String? description,
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  String? rrule,
  String? deletedAt,
}) => <String, dynamic>{
      'summary': summary,
      'description': description,
      'startDt': start.toIso8601String(),
      'endDt': end.toIso8601String(),
      'isAllDay': allDay,
      'rrule': rrule,
      'deletedAt': deletedAt,
    };

Map<String, dynamic> _todo({
  String summary = 'todo',
  String? description,
  DateTime? due,
  String? deletedAt,
}) => <String, dynamic>{
      'summary': summary,
      'description': description,
      'dueDate': due?.toIso8601String(),
      'deletedAt': deletedAt,
    };

Future<void> _insert(
  AppDatabase db, {
  required String id,
  required String type,
  required Map<String, dynamic> payload,
  bool deleted = false,
  String userId = 'user-1',
  int seq = 0,
}) =>
    db.into(db.records).insert(
          RecordRow(
            userId: userId,
            id: id,
            type: type,
            payloadJson: jsonEncode(payload),
            rev: 1,
            deleted: deleted,
            serverTs: DateTime.now().toUtc(),
            seq: seq,
            lastOpId: '',
          ),
        );

Future<List<String>> _ids(
  AppDatabase db, {
  required String userId,
  RecordType? type,
  bool includeTrashed = false,
  bool trashedOnly = false,
  DateTime? from,
  DateTime? to,
  String? dueOn,
  DateTime? dueFrom,
  DateTime? dueTo,
  String? timezone,
  String? search,
  String? cursor,
  int? limit,
}) async {
  final page = await queryRecords(
    db,
    userId: userId,
    type: type,
    includeTrashed: includeTrashed,
    trashedOnly: trashedOnly,
    from: from,
    to: to,
    dueOn: dueOn,
    dueFrom: dueFrom,
    dueTo: dueTo,
    timezone: timezone ?? 'UTC',
    search: search,
    cursor: cursor,
    limit: limit ?? recordQueryDefaultLimit,
  );
  return page.records.map((r) => r.id).toList();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(openDatabase(':memory:'));
  });

  tearDown(() async {
    await db.close();
  });

  test('filters by record type', () async {
    await _insert(db, id: 'ev-1', type: 'event',
        payload: _event(start: _utc(2026, 9, 23, 10), end: _utc(2026, 9, 23, 11)));
    await _insert(db, id: 'td-1', type: 'todo', payload: _todo());

    expect(await _ids(db, userId: 'user-1'), ['ev-1', 'td-1']);
    expect(await _ids(db, userId: 'user-1', type: RecordType.event), ['ev-1']);
    expect(await _ids(db, userId: 'user-1', type: RecordType.todo), ['td-1']);
  });

  test('excludes trashed records by default, includeTrashed adds them back', () async {
    await _insert(db, id: 'live-1', type: 'todo', payload: _todo(summary: 'live 1'));
    await _insert(db, id: 'live-2', type: 'todo', payload: _todo(summary: 'live 2'));
    await _insert(
      db,
      id: 'tomb-1',
      type: 'todo',
      payload: _todo(summary: 'device trash'),
      deleted: true,
    );
    await _insert(
      db,
      id: 'soft-1',
      type: 'todo',
      payload: _todo(summary: 'soft trash', deletedAt: _utc(2026, 9, 20).toIso8601String()),
    );

    final visible = await _ids(db, userId: 'user-1');
    expect(visible, ['live-1', 'live-2']);

    final withTrashed = await _ids(db, userId: 'user-1', includeTrashed: true);
    expect(withTrashed, ['live-1', 'live-2', 'soft-1', 'tomb-1']);
  });

  test('trashedOnly returns only trash; includeTrashed stays a union', () async {
    await _insert(db, id: 'live-1', type: 'todo', payload: _todo(summary: 'live 1'));
    await _insert(db, id: 'live-2', type: 'event',
        payload: _event(start: _utc(2026, 9, 23, 10), end: _utc(2026, 9, 23, 11)));
    await _insert(
      db,
      id: 'tomb-1',
      type: 'todo',
      payload: _todo(summary: 'device trash'),
      deleted: true,
    );
    await _insert(
      db,
      id: 'soft-1',
      type: 'event',
      payload: _event(
        summary: 'soft trash',
        start: _utc(2026, 9, 24, 10),
        end: _utc(2026, 9, 24, 11),
        deletedAt: _utc(2026, 9, 20).toIso8601String(),
      ),
    );

    expect(await _ids(db, userId: 'user-1', trashedOnly: true),
        ['soft-1', 'tomb-1']);
    expect(
      await _ids(db, userId: 'user-1', includeTrashed: true),
      ['live-1', 'live-2', 'soft-1', 'tomb-1'],
      reason: 'includeTrashed keeps its live+trash union semantics',
    );
    expect(
      await _ids(
        db,
        userId: 'user-1',
        includeTrashed: true,
        trashedOnly: true,
      ),
      ['soft-1', 'tomb-1'],
      reason: 'trashedOnly wins when both flags are set',
    );
    expect(
      await _ids(db, userId: 'user-1', type: RecordType.event, trashedOnly: true),
      ['soft-1'],
      reason: 'trashedOnly combines with the type filter',
    );
  });

  test('event window is half-open [from, to) on payload start/end', () async {
    await _insert(db, id: 'ev-span', type: 'event',
        payload: _event(start: _utc(2026, 1, 1, 9), end: _utc(2026, 1, 1, 10)));
    await _insert(db, id: 'ev-later', type: 'event',
        payload: _event(start: _utc(2026, 1, 5, 9), end: _utc(2026, 1, 5, 10)));
    // Ends exactly at the window start: half-open means no overlap.
    await _insert(db, id: 'ev-ends-at-from', type: 'event',
        payload: _event(start: _utc(2025, 12, 31, 23), end: _utc(2026, 1, 1)));
    // Starts exactly at the window end: half-open means no overlap.
    await _insert(db, id: 'ev-starts-at-to', type: 'event',
        payload: _event(start: _utc(2026, 1, 2), end: _utc(2026, 1, 2, 1)));
    await _insert(db, id: 'ev-overlaps-end', type: 'event',
        payload: _event(start: _utc(2026, 1, 1, 23, 30), end: _utc(2026, 1, 2, 1)));

    final ids = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.event,
      from: _utc(2026, 1, 1),
      to: _utc(2026, 1, 2),
    );
    expect(ids, ['ev-overlaps-end', 'ev-span']);
  });

  test('zero-length all-day event occupies its day in the window filter', () async {
    await _insert(db, id: 'allday-zero', type: 'event',
        payload: _event(start: _utc(2026, 3, 5), end: _utc(2026, 3, 5), allDay: true));
    await _insert(db, id: 'allday-full', type: 'event',
        payload: _event(start: _utc(2026, 3, 5), end: _utc(2026, 3, 6), allDay: true));

    // Mid-day window on Mar 5 picks both up.
    final onDay = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.event,
      from: _utc(2026, 3, 5, 12),
      to: _utc(2026, 3, 5, 13),
    );
    expect(onDay, ['allday-full', 'allday-zero']);

    // [Mar 5, Mar 6) half-open: full-day event ends exactly at Mar 6 so a
    // window starting Mar 6 must not see it.
    final nextDay = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.event,
      from: _utc(2026, 3, 6),
      to: _utc(2026, 3, 7),
    );
    expect(nextDay, isEmpty);
  });

  test('rrule masters keep matching the window by DTSTART even when the series began earlier',
      () async {
    await _insert(
      db,
      id: 'series-old',
      type: 'event',
      payload: _event(
        start: _utc(2025, 1, 1, 10),
        end: _utc(2025, 1, 1, 11),
        rrule: 'RRULE:FREQ=DAILY',
      ),
    );
    await _insert(db, id: 'plain-old', type: 'event',
        payload: _event(start: _utc(2025, 1, 1, 10), end: _utc(2025, 1, 1, 11)));
    // Series whose DTSTART is at/after the window end has no instances inside.
    await _insert(
      db,
      id: 'series-future',
      type: 'event',
      payload: _event(
        start: _utc(2026, 6, 1, 10),
        end: _utc(2026, 6, 1, 11),
        rrule: 'RRULE:FREQ=DAILY',
      ),
    );

    final ids = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.event,
      from: _utc(2026, 3, 1),
      to: _utc(2026, 3, 8),
    );
    expect(ids, ['series-old']);
  });

  test('search matches summary and description case-insensitively with LIKE escaping',
      () async {
    await _insert(db, id: 'ev-1', type: 'event',
        payload: _event(summary: 'Project Alpha review', start: _utc(2026, 9, 1), end: _utc(2026, 9, 1, 1)));
    await _insert(db, id: 'td-1', type: 'todo',
        payload: _todo(summary: 'Deploy', description: 'Ship the WEB pipeline'));
    await _insert(db, id: 'td-2', type: 'todo', payload: _todo(summary: '100% done soon'));
    await _insert(db, id: 'td-3', type: 'todo', payload: _todo(summary: '100x scale'));

    expect(await _ids(db, userId: 'user-1', search: 'project alpha'), ['ev-1']);
    expect(await _ids(db, userId: 'user-1', search: 'WEB'), ['td-1']);
    // Bare % must match literally, not as a wildcard.
    expect(await _ids(db, userId: 'user-1', search: '100%'), ['td-2']);
    expect(await _ids(db, userId: 'user-1', search: 'nothing-here'), isEmpty);
  });

  test('dueOn computes the local day bounds in the given timezone, defaulting to UTC',
      () async {
    await _insert(db, id: 'td-in-shanghai-morning', type: 'todo',
        payload: _todo(due: _utc(2026, 9, 23, 2)));
    // 2026-09-22T16:00Z is exactly 2026-09-23T00:00+08:00 — inclusive start.
    await _insert(db, id: 'td-in-shanghai-start', type: 'todo',
        payload: _todo(due: _utc(2026, 9, 22, 16)));
    // An hour earlier lands on Sep 22 local time.
    await _insert(db, id: 'td-out-shanghai-early', type: 'todo',
        payload: _todo(due: _utc(2026, 9, 22, 15)));
    // 2026-09-23T16:00Z is 2026-09-24T00:00+08:00 — exclusive end.
    await _insert(db, id: 'td-out-shanghai-end', type: 'todo',
        payload: _todo(due: _utc(2026, 9, 23, 16)));
    await _insert(db, id: 'td-no-due', type: 'todo', payload: _todo());

    final shanghai = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.todo,
      dueOn: '2026-09-23',
      timezone: 'Asia/Shanghai',
    );
    expect(shanghai, ['td-in-shanghai-morning', 'td-in-shanghai-start']);

    // Same dueOn without a timezone uses UTC day bounds: Sep23 16Z is still
    // inside the UTC day while it already fell on Sep 24 in Shanghai.
    final utcDay = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.todo,
      dueOn: '2026-09-23',
    );
    expect(utcDay, ['td-in-shanghai-morning', 'td-out-shanghai-end']);
  });

  test('dueFrom is inclusive and dueTo is exclusive on payload dueDate', () async {
    await _insert(db, id: 'td-a', type: 'todo', payload: _todo(due: _utc(2026, 9, 1)));
    await _insert(db, id: 'td-b', type: 'todo', payload: _todo(due: _utc(2026, 9, 15)));
    await _insert(db, id: 'td-c', type: 'todo', payload: _todo(due: _utc(2026, 10, 1)));

    final ids = await _ids(
      db,
      userId: 'user-1',
      type: RecordType.todo,
      dueFrom: _utc(2026, 9, 1),
      dueTo: _utc(2026, 10, 1),
    );
    expect(ids, ['td-a', 'td-b']);
  });

  test('paginates with a stable id cursor, default limit 50, hard cap 200', () async {
    for (var i = 0; i < 60; i++) {
      await _insert(db, id: 'page-${i.toString().padLeft(3, '0')}', type: 'todo',
          payload: _todo(summary: 'p$i'));
    }

    final first = await queryRecords(db, userId: 'user-1', limit: 2);
    expect(first.records.map((r) => r.id), ['page-000', 'page-001']);
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, 'page-001');

    final second = await queryRecords(db, userId: 'user-1', cursor: first.nextCursor, limit: 2);
    expect(second.records.map((r) => r.id), ['page-002', 'page-003']);

    // Full sweep: no gaps, no duplicates, terminates with hasMore=false.
    final seen = <String>[];
    String? cursor;
    while (true) {
      final page = await queryRecords(db, userId: 'user-1', cursor: cursor, limit: 17);
      seen.addAll(page.records.map((r) => r.id));
      if (!page.hasMore) {
        expect(page.nextCursor, isNull);
        break;
      }
      cursor = page.nextCursor;
      expect(cursor, isNotNull);
    }
    expect(seen, hasLength(60));
    expect(seen.toSet(), hasLength(60));

    final defaulted = await queryRecords(db, userId: 'user-1');
    expect(defaulted.records, hasLength(recordQueryDefaultLimit));
    expect(defaulted.hasMore, isTrue);

    for (var i = 60; i < 210; i++) {
      await _insert(db, id: 'page-${i.toString().padLeft(3, '0')}', type: 'todo',
          payload: _todo(summary: 'p$i'));
    }
    final capped = await queryRecords(db, userId: 'user-1', limit: 999);
    expect(capped.records, hasLength(recordQueryMaxLimit));
    expect(capped.hasMore, isTrue);
  });

  // Proven-flip instant: julianday's ~73µs double ulp at 2026 epoch makes
  // the old float window clause exclude rows the Dart overlap admits at
  // these sub-ulp gaps (4995/5000 sampled instants flip).
  group('window boundary microsecond precision', () {
    final edge = DateTime.utc(2026, 6, 1, 0, 0, 1, 13);

    test('from = event end - 50us admits the row and its expansion', () async {
      await _insert(db, id: 'ev-tiny-gap', type: 'event',
          payload: _event(start: DateTime.utc(2026, 6, 1), end: edge));
      final from = edge.subtract(const Duration(microseconds: 50));
      final to = edge.add(const Duration(seconds: 1));

      expect(
        await _ids(db, userId: 'user-1', type: RecordType.event,
            from: from, to: to),
        ['ev-tiny-gap'],
      );
      final page = await queryRecords(
          db, userId: 'user-1', type: RecordType.event, from: from, to: to);
      final expansion =
          expandRecordsInWindow(page.records, from: from, to: to);
      expect(expansion.instances.map((i) => i.master.id), ['ev-tiny-gap']);
    });

    test('from = event end exactly excludes the row on both sides', () async {
      await _insert(db, id: 'ev-edge', type: 'event',
          payload: _event(start: DateTime.utc(2026, 6, 1), end: edge));
      final from = edge;
      final to = edge.add(const Duration(seconds: 1));

      expect(
        await _ids(db, userId: 'user-1', type: RecordType.event,
            from: from, to: to),
        isEmpty,
      );
      final page = await queryRecords(
          db, userId: 'user-1', type: RecordType.event, from: from, to: to);
      final expansion =
          expandRecordsInWindow(page.records, from: from, to: to);
      expect(expansion.instances, isEmpty);
    });

    test(
        'zero-length event admitted at from = start + 1h - 10us, excluded at start + 1h',
        () async {
      await _insert(db, id: 'ev-zero', type: 'event',
          payload: _event(start: edge, end: edge));
      final oneHour = edge.add(const Duration(hours: 1));

      final admittedFrom = oneHour.subtract(const Duration(microseconds: 10));
      expect(
        await _ids(db, userId: 'user-1', type: RecordType.event,
            from: admittedFrom, to: edge.add(const Duration(hours: 2))),
        ['ev-zero'],
      );
      final page = await queryRecords(
        db,
        userId: 'user-1',
        type: RecordType.event,
        from: admittedFrom,
        to: edge.add(const Duration(hours: 2)),
      );
      final expansion = expandRecordsInWindow(
          page.records,
          from: admittedFrom,
          to: edge.add(const Duration(hours: 2)));
      expect(expansion.instances.map((i) => i.master.id), ['ev-zero']);
      expect(expansion.instances.single.start, edge);
      expect(expansion.instances.single.end, oneHour);

      expect(
        await _ids(db, userId: 'user-1', type: RecordType.event,
            from: oneHour, to: edge.add(const Duration(hours: 2))),
        isEmpty,
      );
    });

    test(
        'zero-length all-day event admitted at from = start + 24h - 10us, excluded at start + 24h',
        () async {
      final dayStart = DateTime.utc(2026, 6, 1);
      await _insert(db, id: 'allday-zero-edge', type: 'event',
          payload: _event(start: dayStart, end: dayStart, allDay: true));
      final nextDay = dayStart.add(const Duration(days: 1));

      final admittedFrom = nextDay.subtract(const Duration(microseconds: 10));
      expect(
        await _ids(db, userId: 'user-1', type: RecordType.event,
            from: admittedFrom, to: dayStart.add(const Duration(days: 2))),
        ['allday-zero-edge'],
      );
      expect(
        await _ids(db, userId: 'user-1', type: RecordType.event,
            from: nextDay, to: dayStart.add(const Duration(days: 2))),
        isEmpty,
      );
    });
  });

  group('rrule window expansion', () {
    Future<List<String>> expandIds({
      required DateTime from,
      required DateTime to,
      int cap = windowExpansionCap,
    }) async {
      final page = await queryRecords(
        db,
        userId: 'user-1',
        type: RecordType.event,
        from: from,
        to: to,
      );
      final expansion = expandRecordsInWindow(page.records, from: from, to: to, cap: cap);
      return expansion.instances
          .map((i) => '${i.master.id}@${i.start.toIso8601String()}')
          .toList();
    }

    test('daily series yields one instance per day inside the window', () async {
      await _insert(
        db,
        id: 'daily-1',
        type: 'event',
        payload: _event(
          summary: 'standup',
          start: _utc(2026, 1, 1, 10),
          end: _utc(2026, 1, 1, 10, 30),
          rrule: 'RRULE:FREQ=DAILY',
        ),
      );

      final ids = await expandIds(from: _utc(2026, 1, 5), to: _utc(2026, 1, 8));
      expect(ids, [
        'daily-1@2026-01-05T10:00:00.000Z',
        'daily-1@2026-01-06T10:00:00.000Z',
        'daily-1@2026-01-07T10:00:00.000Z',
      ]);
    });

    test('expansion includes an instance that only partially overlaps the window start',
        () async {
      await _insert(
        db,
        id: 'daily-1',
        type: 'event',
        payload: _event(
          start: _utc(2026, 1, 1, 10),
          end: _utc(2026, 1, 1, 11),
          rrule: 'RRULE:FREQ=DAILY',
        ),
      );

      // Instance [10:00, 11:00) overlaps a window starting at 10:30.
      final ids = await expandIds(from: _utc(2026, 1, 5, 10, 30), to: _utc(2026, 1, 6));
      expect(ids, ['daily-1@2026-01-05T10:00:00.000Z']);
    });

    test('caps the expansion at 500 instances and sets the truncated flag', () async {
      await _insert(
        db,
        id: 'long-series',
        type: 'event',
        payload: _event(
          start: _utc(2026, 1, 1, 9),
          end: _utc(2026, 1, 1, 10),
          rrule: 'RRULE:FREQ=DAILY',
        ),
      );

      final page = await queryRecords(
        db,
        userId: 'user-1',
        type: RecordType.event,
        from: _utc(2026, 1, 1),
        to: _utc(2028, 1, 1),
      );
      final expansion = expandRecordsInWindow(
        page.records,
        from: _utc(2026, 1, 1),
        to: _utc(2028, 1, 1),
      );
      expect(expansion.instances, hasLength(windowExpansionCap));
      expect(expansion.truncated, isTrue);

      final underCap = expandRecordsInWindow(
        page.records,
        from: _utc(2026, 1, 1),
        to: _utc(2026, 1, 4),
      );
      expect(underCap.instances, hasLength(3));
      expect(underCap.truncated, isFalse);
    });

    test('invalid rrule falls back to raw [start,end) overlap and notes the master',
        () async {
      await _insert(
        db,
        id: 'bad-rrule-in',
        type: 'event',
        payload: _event(start: _utc(2026, 2, 2, 9), end: _utc(2026, 2, 2, 10), rrule: 'garbage'),
      );
      await _insert(
        db,
        id: 'bad-rrule-out',
        type: 'event',
        // DTSTART precedes the window but the raw interval does not overlap:
        // the row is still a candidate master, so the fallback must note it.
        payload: _event(start: _utc(2025, 5, 2, 9), end: _utc(2025, 5, 2, 10), rrule: 'garbage'),
      );

      final page = await queryRecords(
        db,
        userId: 'user-1',
        type: RecordType.event,
        from: _utc(2026, 2, 1),
        to: _utc(2026, 3, 1),
      );
      final expansion = expandRecordsInWindow(
        page.records,
        from: _utc(2026, 2, 1),
        to: _utc(2026, 3, 1),
      );
      expect(
        expansion.instances.map((i) => i.master.id),
        ['bad-rrule-in'],
      );
      expect(expansion.instances.single.start, _utc(2026, 2, 2, 9));
      expect(
        expansion.invalidRruleIds.toSet(),
        {'bad-rrule-in', 'bad-rrule-out'},
      );
      expect(expansion.truncated, isFalse);
    });

    test('non-recurring event expands to a singleton only when it overlaps', () async {
      await _insert(db, id: 'plain-in', type: 'event',
          payload: _event(start: _utc(2026, 4, 2, 9), end: _utc(2026, 4, 2, 10)));
      await _insert(db, id: 'plain-out', type: 'event',
          payload: _event(start: _utc(2026, 7, 2, 9), end: _utc(2026, 7, 2, 10)));

      final page = await queryRecords(
        db,
        userId: 'user-1',
        type: RecordType.event,
        from: _utc(2026, 4, 1),
        to: _utc(2026, 5, 1),
      );
      final expansion = expandRecordsInWindow(
        page.records,
        from: _utc(2026, 4, 1),
        to: _utc(2026, 5, 1),
      );
      expect(expansion.instances.map((i) => i.master.id), ['plain-in']);
      expect(expansion.instances.single.start, _utc(2026, 4, 2, 9));
      expect(expansion.instances.single.end, _utc(2026, 4, 2, 10));
      expect(expansion.invalidRruleIds, isEmpty);
    });

    test('all-day instances honor half-open [start,end) overlap', () async {
      await _insert(db, id: 'allday-1', type: 'event',
          payload: _event(start: _utc(2026, 3, 5), end: _utc(2026, 3, 6), allDay: true));

      final inside = expandRecordsInWindow(
        [await _row(db, 'allday-1')],
        from: _utc(2026, 3, 5),
        to: _utc(2026, 3, 6),
      );
      expect(inside.instances, hasLength(1));

      final after = expandRecordsInWindow(
        [await _row(db, 'allday-1')],
        from: _utc(2026, 3, 6),
        to: _utc(2026, 3, 7),
      );
      expect(after.instances, isEmpty);

      final before = expandRecordsInWindow(
        [await _row(db, 'allday-1')],
        from: _utc(2026, 3, 4),
        to: _utc(2026, 3, 5),
      );
      expect(before.instances, isEmpty);

      final midDay = expandRecordsInWindow(
        [await _row(db, 'allday-1')],
        from: _utc(2026, 3, 5, 23),
        to: _utc(2026, 3, 6, 1),
      );
      expect(midDay.instances, hasLength(1));
    });
  });
}

Future<RecordRow> _row(AppDatabase db, String id) => (db.select(db.records)
      ..where((t) => t.id.equals(id)))
    .getSingle();
