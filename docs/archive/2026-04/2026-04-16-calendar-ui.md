# Calendar UI Implementation Plan
> ⚠️ **已过时（2026-09-27 标注，正文原样保留仅供考古）**：本文是 2026-04 项目早期的方案讨论，CalDAV 路线已被自研同步后端替代（v0.22.0 落地），内容不再维护。现行状态唯一源：`calendar_todo_app/docs/START_HERE.md`（接续入口）、`calendar_todo_app/docs/ROADMAP.md`（功能全景）。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现完整的日历 UI——日/周/月视图切换、事件显示、事件创建/编辑/删除——与 Phase 1 的 Drift 数据库和 Riverpod 状态管理集成。

**Architecture:** 使用 `kalender` 包渲染日历视图。通过自定义 `CalendaEvent` 子类桥接 Drift `Event` 数据模型和 kalender 的 `CalendarEvent`。Riverpod providers 负责从数据库读取事件并注入 kalender 的 `EventsController`。

**Tech Stack:** kalender ^0.16.0 / Riverpod / Drift / go_router

---

## File Structure

```
lib/
├── core/
│   ├── router/
│   │   └── app_router.dart              # 修改：添加 event 路由
│   └── theme/
│       └── ...                          # 不变
├── data/
│   └── local/
│       └── database/
│           └── ...                      # 不变
├── domain/
│   ├── providers/
│   │   ├── database_provider.dart       # Riverpod: AppDatabase 单例
│   │   └── events_provider.dart         # Riverpod: 事件查询 providers
│   └── models/
│       └── calendar_event_adapter.dart  # kalender CalendarEvent 适配器
└── ui/
    ├── pages/
    │   ├── home/
    │   │   └── home_page.dart           # 修改：替换骨架为实际布局
    │   └── event/
    │       ├── event_create_page.dart   # 新建事件页面
    │       └── event_edit_page.dart     # 编辑事件页面
    └── widgets/
        ├── calendar/
        │   ├── calendar_section.dart    # 日历视图区域（封装 kalender）
        │   ├── event_tile.dart          # 日历内事件瓦片
        │   └── view_switcher.dart       # 日/周/月切换控件
        └── common/
            └── date_time_field.dart     # 日期时间选择器字段
test/
├── domain/
│   ├── providers/
│   │   └── events_provider_test.dart
│   └── models/
│       └── calendar_event_adapter_test.dart
└── ui/
    └── widgets/
        └── calendar/
            └── event_tile_test.dart
```

---

## Task 1: Add kalender Dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add kalender to pubspec.yaml**

Add `kalender: ^0.16.0` under `dependencies:` in `pubspec.yaml`.

Also add `timezone` and `intl` packages which kalender needs:

```yaml
  # Calendar UI
  kalender: ^0.16.0
  timezone: any
  intl: any
```

- [ ] **Step 2: Run flutter pub get**

```bash
flutter pub get
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add kalender, timezone, intl dependencies"
```

---

## Task 2: Calendar Event Adapter

**Files:**
- Create: `lib/domain/models/calendar_event_adapter.dart`
- Test: `test/domain/models/calendar_event_adapter_test.dart`

This is the bridge between Drift's `Event` model and kalender's `CalendarEvent`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/models/calendar_event_adapter_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

void main() {
  group('CalendaEventAdapter', () {
    test('creates from manual fields', () {
      final adapter = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'test-uid',
        title: 'Team Meeting',
        description: 'Weekly sync',
        color: const Color(0xFF2563EB),
        start: DateTime(2026, 4, 17, 10),
        end: DateTime(2026, 4, 17, 11),
      );

      expect(adapter.drifId, 1);
      expect(adapter.title, 'Team Meeting');
      expect(adapter.dateTimeRange.start, DateTime(2026, 4, 17, 10));
      expect(adapter.dateTimeRange.end, DateTime(2026, 4, 17, 11));
      expect(adapter.description, 'Weekly sync');
      expect(adapter.color, const Color(0xFF2563EB));
    });

    test('copyWith preserves id', () {
      final original = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'uid',
        title: 'Old Title',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );

      final copied = original.copyWith(title: 'New Title');
      expect(copied.title, 'New Title');
      expect(copied.id, original.id); // id preserved
      expect(copied.drifId, 1);
    });

    test('equality works', () {
      final a = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'uid',
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );
      final b = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'uid',
        title: 'Event',
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1, 1),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toCompanion converts to Drift EventsCompanion for create', () {
      final adapter = CalendaEventAdapter(
        drifId: 0,
        calendarId: 5,
        uid: 'new-uid',
        title: 'New Event',
        description: 'Desc',
        start: DateTime(2026, 4, 17, 10),
        end: DateTime(2026, 4, 17, 11),
        isAllDay: false,
      );

      final companion = adapter.toCreateCompanion();
      expect(companion.calendarId.value, 5);
      expect(companion.summary.value, 'New Event');
      expect(companion.startDt.value, DateTime(2026, 4, 17, 10));
      expect(companion.endDt.value, DateTime(2026, 4, 17, 11));
      expect(companion.isAllDay.value, false);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/domain/models/calendar_event_adapter_test.dart
```

- [ ] **Step 3: Write implementation**

```dart
// lib/domain/models/calendar_event_adapter.dart
import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart' as drift;

/// Bridge between Drift Event and kalender CalendarEvent.
///
/// kalender requires extending [CalendarEvent]. This class holds all
/// the extra fields from our database model while satisfying kalender's API.
class CalendaEventAdapter extends CalendarEvent {
  final int drifId;
  final int calendarId;
  final String uid;
  final String title;
  final String? description;
  final String? location;
  final Color? color;
  final bool isAllDay;
  final String? rrule;
  final bool isDirty;

  CalendaEventAdapter({
    required this.drifId,
    required this.calendarId,
    required this.uid,
    required this.title,
    required DateTime start,
    required DateTime end,
    this.description,
    this.location,
    this.color,
    this.isAllDay = false,
    this.rrule,
    this.isDirty = false,
  }) : super(dateTimeRange: DateTimeRange(start: start, end: end));

  /// Create from a Drift [Event] row.
  factory CalendaEventAdapter.fromDrift(drift.Event e, {Color? calendarColor}) {
    return CalendaEventAdapter(
      drifId: e.id,
      calendarId: e.calendarId,
      uid: e.uid,
      title: e.summary,
      start: e.startDt,
      end: e.endDt,
      description: e.description,
      location: e.location,
      color: calendarColor,
      isAllDay: e.isAllDay,
      rrule: e.rrule,
      isDirty: e.isDirty,
    );
  }

  @override
  CalendaEventAdapter copyWith({
    DateTimeRange? dateTimeRange,
    String? title,
    String? description,
    String? location,
    Color? color,
    bool? isAllDay,
    String? rrule,
    bool? isDirty,
  }) {
    final updated = CalendaEventAdapter(
      drifId: drifId,
      calendarId: calendarId,
      uid: uid,
      title: title ?? this.title,
      start: dateTimeRange?.start ?? dateTimeRange.start,
      end: dateTimeRange?.end ?? dateTimeRange.end,
      description: description ?? this.description,
      location: location ?? this.location,
      color: color ?? this.color,
      isAllDay: isAllDay ?? this.isAllDay,
      rrule: rrule ?? this.rrule,
      isDirty: isDirty ?? this.isDirty,
    );
    updated.id = id;
    return updated;
  }

  /// Convert to a Drift [EventsCompanion] for creating a new row.
  drift.EventsCompanion toCreateCompanion() {
    return drift.EventsCompanion.insert(
      calendarId: calendarId,
      uid: uid,
      summary: title,
      startDt: dateTimeRange.start,
      endDt: dateTimeRange.end,
      isAllDay: isAllDay,
      description: drift.Value(description),
      location: drift.Value(location),
      rrule: drift.Value(rrule),
    );
  }

  /// Convert to a Drift [EventsCompanion] for updating an existing row.
  drift.EventsCompanion toUpdateCompanion() {
    return drift.EventsCompanion(
      id: drift.Value(drifId),
      calendarId: drift.Value(calendarId),
      uid: drift.Value(uid),
      summary: drift.Value(title),
      startDt: drift.Value(dateTimeRange.start),
      endDt: drift.Value(dateTimeRange.end),
      isAllDay: drift.Value(isAllDay),
      description: drift.Value(description),
      location: drift.Value(location),
      rrule: drift.Value(rrule),
      isDirty: drift.Value(true),
      updatedAt: drift.Value(DateTime.now()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (super == other &&
          other is CalendaEventAdapter &&
          other.drifId == drifId &&
          other.title == title &&
          other.description == description &&
          other.color == color &&
          other.isAllDay == isAllDay);

  @override
  int get hashCode =>
      Object.hash(super.hashCode, drifId, title, description, color, isAllDay);
}
```

Note: The `drift.Value` import is needed. Add `import 'package:drift/drift.dart' show Value;` or import the database file with a prefix.

- [ ] **Step 4: Run tests**

```bash
flutter test test/domain/models/calendar_event_adapter_test.dart
```

Expected: 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/ test/domain/models/
git commit -m "feat: add CalendaEventAdapter bridging Drift Event and kalender"
```

---

## Task 3: Riverpod Providers (Database + Events)

**Files:**
- Create: `lib/domain/providers/database_provider.dart`
- Create: `lib/domain/providers/events_provider.dart`
- Test: `test/domain/providers/events_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/providers/events_provider_test.dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/domain/providers/database_provider.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase testDb;

  setUp(() {
    testDb = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(testDb)],
    );
  });

  tearDown(() async {
    container.dispose();
    await testDb.close();
  });

  group('eventsProvider', () {
    test('eventsInDateRangeProvider returns events in range', () async {
      // Insert a calendar first
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
              color: '#2563EB',
              timezone: 'UTC',
            ),
          );

      // Insert events
      await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e1',
              summary: 'April Event',
              startDt: DateTime(2026, 4, 15, 10),
              endDt: DateTime(2026, 4, 15, 11),
              isAllDay: false,
            ),
          );
      await testDb.into(testDb.events).insert(
            EventsCompanion.insert(
              calendarId: calId,
              uid: 'e2',
              summary: 'May Event',
              startDt: DateTime(2026, 5, 1),
              endDt: DateTime(2026, 5, 1, 1),
              isAllDay: false,
            ),
          );

      // Query April range
      final events = await container.read(
        eventsInDateRangeProvider(
          DateTimeRange(
            start: DateTime(2026, 4, 1),
            end: DateTime(2026, 4, 30),
          ),
        ).future,
      );

      expect(events.length, 1);
      expect(events.first.summary, 'April Event');
    });

    test('createEventProvider inserts event and returns id', () async {
      final calId = await testDb.into(testDb.calendars).insert(
            CalendarsCompanion.insert(
              caldavHref: '/cal/',
              name: 'Test',
              color: '#000',
              timezone: 'UTC',
            ),
          );

      final id = await container.read(createEventProvider).call(
            calendarId: calId,
            uid: 'new-uid',
            summary: 'New Event',
            startDt: DateTime(2026, 6, 1),
            endDt: DateTime(2026, 6, 1, 1),
            isAllDay: false,
          );

      expect(id, greaterThan(0));

      final event = await (testDb.select(testDb.events)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(event.summary, 'New Event');
    });
  });
}
```

- [ ] **Step 2: Create database provider**

```dart
// lib/domain/providers/database_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';

/// Provides the singleton AppDatabase instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
```

- [ ] **Step 3: Create events provider**

```dart
// lib/domain/providers/events_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/data/local/database/app_database.dart';
import 'package:calendar_todo_app/domain/providers/database_provider.dart';

/// Watch events in a date range. Returns a Stream that emits on every change.
final eventsInDateRangeProvider =
    StreamProvider.family<List<Event>, DateTimeRange>(
  (ref, range) {
    final db = ref.watch(databaseProvider);
    return db.eventsDao.watchByDateRange(range.start, range.end);
  },
);

/// Watch all active calendars.
final calendarsProvider = StreamProvider<List<Calendar>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.calendarsDao.watchAll();
});

/// Utility to create a new event.
final createEventProvider = Provider<Future<int> Function({
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime startDt,
  required DateTime endDt,
  required bool isAllDay,
  String? description,
  String? location,
})>((ref) {
  final db = ref.watch(databaseProvider);
  return ({
    required calendarId,
    required uid,
    required summary,
    required startDt,
    required endDt,
    required isAllDay,
    description,
    location,
  }) async {
    return db.into(db.events).insert(
          EventsCompanion.insert(
            calendarId: calendarId,
            uid: uid,
            summary: summary,
            startDt: startDt,
            endDt: endDt,
            isAllDay: isAllDay,
            description: Value(description),
            location: Value(location),
          ),
        );
  };
});

/// Utility to delete an event by id.
final deleteEventProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  return (int id) async {
    await (db.delete(db.events)..where((t) => t.id.equals(id))).go();
  };
});
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/domain/providers/events_provider_test.dart
```

Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/providers/ test/domain/providers/
git commit -m "feat: add Riverpod providers for database, events, and calendars"
```

---

## Task 4: Event Tile Widget

**Files:**
- Create: `lib/ui/widgets/calendar/event_tile.dart`
- Test: `test/ui/widgets/calendar/event_tile_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/widgets/calendar/event_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/event_tile.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

void main() {
  group('EventTile', () {
    testWidgets('renders event title and time', (tester) async {
      final event = CalendaEventAdapter(
        drifId: 1,
        calendarId: 10,
        uid: 'test',
        title: 'Team Meeting',
        start: DateTime(2026, 4, 17, 10, 0),
        end: DateTime(2026, 4, 17, 11, 0),
        color: const Color(0xFF2563EB),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTile(event: event, tileRange: null),
          ),
        ),
      );

      expect(find.text('Team Meeting'), findsOneWidget);
    });

    testWidgets('renders all-day event without time', (tester) async {
      final event = CalendaEventAdapter(
        drifId: 2,
        calendarId: 10,
        uid: 'allday',
        title: 'Birthday',
        start: DateTime(2026, 4, 17),
        end: DateTime(2026, 4, 18),
        color: const Color(0xFF16A34A),
        isAllDay: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTile(event: event, tileRange: null),
          ),
        ),
      );

      expect(find.text('Birthday'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Create EventTile widget**

```dart
// lib/ui/widgets/calendar/event_tile.dart
import 'package:flutter/material.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

/// Renders a single event inside the calendar view.
class EventTile extends StatelessWidget {
  final CalendaEventAdapter event;
  final dynamic tileRange; // nullable, kalender passes DateTimeRange

  const EventTile({
    super.key,
    required this.event,
    this.tileRange,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = event.color ?? AppColors.lightAccent;

    return Container(
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: bgColor, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: bgColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!event.isAllDay)
            Text(
              _formatTime(event.dateTimeRange.start),
              style: TextStyle(
                fontSize: 10,
                color: bgColor.withValues(alpha: 0.8),
              ),
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
```

- [ ] **Step 3: Run tests**

```bash
flutter test test/ui/widgets/calendar/event_tile_test.dart
```

Expected: 2 tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/calendar/event_tile.dart test/ui/widgets/calendar/event_tile_test.dart
git commit -m "feat: add EventTile widget for calendar event rendering"
```

---

## Task 5: View Switcher Widget

**Files:**
- Create: `lib/ui/widgets/calendar/view_switcher.dart`

- [ ] **Step 1: Create view switcher**

```dart
// lib/ui/widgets/calendar/view_switcher.dart
import 'package:flutter/material.dart';

/// Calendar view mode.
enum CalendarViewMode { day, week, month }

/// A segmented control to switch between day/week/month views.
class ViewSwitcher extends StatelessWidget {
  final CalendarViewMode currentMode;
  final ValueChanged<CalendarViewMode> onModeChanged;

  const ViewSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CalendarViewMode>(
      segments: const [
        ButtonSegment(value: CalendarViewMode.day, label: Text('Day')),
        ButtonSegment(value: CalendarViewMode.week, label: Text('Week')),
        ButtonSegment(value: CalendarViewMode.month, label: Text('Month')),
      ],
      selected: {currentMode},
      onSelectionChanged: (s) => onModeChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/widgets/calendar/view_switcher.dart
git commit -m "feat: add ViewSwitcher for day/week/month mode switching"
```

---

## Task 6: Calendar Section Widget

**Files:**
- Create: `lib/ui/widgets/calendar/calendar_section.dart`

This is the main calendar widget that wraps `kalender`'s `CalendarView`.

- [ ] **Step 1: Create CalendarSection**

```dart
// lib/ui/widgets/calendar/calendar_section.dart
import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/event_tile.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/view_switcher.dart';

/// Encapsulates the kalender CalendarView with view switching.
class CalendarSection extends StatefulWidget {
  final List<CalendaEventAdapter> events;
  final void Function(CalendaEventAdapter event)? onEventTapped;
  final void Function(DateTimeRange range)? onTimeSlotTapped;

  const CalendarSection({
    super.key,
    required this.events,
    this.onEventTapped,
    this.onTimeSlotTapped,
  });

  @override
  State<CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<CalendarSection> {
  CalendarViewMode _viewMode = CalendarViewMode.week;
  final _calendarController = CalendarController();
  final _eventsController = DefaultEventsController();

  @override
  void didUpdateWidget(CalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != oldWidget.events) {
      _syncEvents();
    }
  }

  void _syncEvents() {
    // Clear and re-add all events from the provider.
    _eventsController.clearEvents();
    for (final event in widget.events) {
      _eventsController.addEvent(event);
    }
  }

  @override
  void dispose() {
    _calendarController.dispose();
    _eventsController.dispose();
    super.dispose();
  }

  ViewConfiguration _viewConfig() {
    switch (_viewMode) {
      case CalendarViewMode.day:
        return MultiDayViewConfiguration.singleDay();
      case CalendarViewMode.week:
        return MultiDayViewConfiguration.week();
      case CalendarViewMode.month:
        return MonthViewConfiguration.singleMonth();
    }
  }

  TileComponents _tileComponents() {
    return TileComponents(
      tileBuilder: (event, tileRange) {
        final adapter = event as CalendaEventAdapter;
        return EventTile(event: adapter, tileRange: tileRange);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar: view switcher + navigation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Today button
              TextButton(
                onPressed: () {
                  _calendarController.jumpToDate(DateTime.now());
                },
                child: const Text('Today'),
              ),
              const Spacer(),
              // Previous / Next
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _calendarController.animateToPreviousPage(),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _calendarController.animateToNextPage(),
              ),
              const SizedBox(width: 8),
              ViewSwitcher(
                currentMode: _viewMode,
                onModeChanged: (mode) {
                  setState(() {
                    _viewMode = mode;
                  });
                },
              ),
            ],
          ),
        ),
        // Calendar view
        Expanded(
          child: CalendarView(
            eventsController: _eventsController,
            calendarController: _calendarController,
            viewConfiguration: _viewConfig(),
            callbacks: CalendarCallbacks(
              onEventTapped: (event) {
                if (widget.onEventTapped != null) {
                  widget.onEventTapped!(event as CalendaEventAdapter);
                }
              },
              onTapped: (datetime) {
                if (widget.onTimeSlotTapped != null) {
                  widget.onTimeSlotTapped!(
                    DateTimeRange(
                      start: datetime,
                      end: datetime.add(const Duration(hours: 1)),
                    ),
                  );
                }
              },
            ),
            header: CalendarHeader(
              multiDayTileComponents: _tileComponents(),
            ),
            body: CalendarBody(
              multiDayTileComponents: _tileComponents(),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/widgets/calendar/calendar_section.dart
git commit -m "feat: add CalendarSection wrapping kalender with view switching"
```

---

## Task 7: Event Create Page

**Files:**
- Create: `lib/ui/pages/event/event_create_page.dart`

- [ ] **Step 1: Create event creation page**

```dart
// lib/ui/pages/event/event_create_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/core/theme/app_colors.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';

/// Page for creating a new calendar event.
class EventCreatePage extends ConsumerStatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;

  const EventCreatePage({
    super.key,
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  ConsumerState<EventCreatePage> createState() => _EventCreatePageState();
}

class _EventCreatePageState extends ConsumerState<EventCreatePage> {
  late DateTime _start;
  late DateTime _end;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isAllDay = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No calendar available. Add one in Settings.')),
          );
        }
        return;
      }

      final createEvent = ref.read(createEventProvider);
      await createEvent(
        calendarId: calendars.first.id,
        uid: 'local-${DateTime.now().millisecondsSinceEpoch}',
        summary: _titleController.text.trim(),
        startDt: _start,
        endDt: _end,
        isAllDay: _isAllDay,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    if (!_isAllDay) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(isStart ? _start : _end),
      );
      if (time == null || !mounted) return;

      final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      setState(() {
        if (isStart) {
          _start = dt;
        } else {
          _end = dt;
        }
      });
    } else {
      setState(() {
        if (isStart) {
          _start = DateTime(date.year, date.month, date.day);
        } else {
          _end = DateTime(date.year, date.month, date.day);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('New Event'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          // All-day toggle
          SwitchListTile(
            value: _isAllDay,
            onChanged: (v) => setState(() => _isAllDay = v),
            title: const Text('All day'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),

          // Start date/time
          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: Text(_isAllDay ? 'Starts' : 'Starts at'),
            subtitle: Text(_formatDateTime(_start)),
            onTap: () => _pickDateTime(true),
            contentPadding: EdgeInsets.zero,
          ),

          // End date/time
          ListTile(
            leading: const Icon(Icons.stop_outlined),
            title: Text(_isAllDay ? 'Ends' : 'Ends at'),
            subtitle: Text(_formatDateTime(_end)),
            onTap: () => _pickDateTime(false),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          // Location
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Location',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    if (_isAllDay) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/pages/event/event_create_page.dart
git commit -m "feat: add EventCreatePage with title, date/time, description, location"
```

---

## Task 8: Event Edit Page

**Files:**
- Create: `lib/ui/pages/event/event_edit_page.dart`

- [ ] **Step 1: Create event edit page**

```dart
// lib/ui/pages/event/event_edit_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';

/// Page for editing or deleting an existing event.
class EventEditPage extends ConsumerStatefulWidget {
  final CalendaEventAdapter event;

  const EventEditPage({super.key, required this.event});

  @override
  ConsumerState<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends ConsumerState<EventEditPage> {
  late CalendaEventAdapter _event;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _titleController.text = _event.title;
    _descriptionController.text = _event.description ?? '';
    _locationController.text = _event.location ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final updated = _event.copyWith(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
      );
      await (db.update(db.events)..where((t) => t.id.equals(_event.drifId)))
          .write(updated.toUpdateCompanion());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "${_event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.lightError),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(deleteEventProvider)(_event.drifId);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickDateTime(bool isStart) async {
    final current = isStart ? _event.dateTimeRange.start : _event.dateTimeRange.end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _event = _event.copyWith(
          dateTimeRange: DateTimeRange(start: dt, end: _event.dateTimeRange.end),
        );
      } else {
        _event = _event.copyWith(
          dateTimeRange: DateTimeRange(start: _event.dateTimeRange.start, end: dt),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Import for AppColors
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Edit Event'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
            tooltip: 'Delete',
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('Starts at'),
            subtitle: Text(_formatDateTime(_event.dateTimeRange.start)),
            onTap: () => _pickDateTime(true),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.stop_outlined),
            title: const Text('Ends at'),
            subtitle: Text(_formatDateTime(_event.dateTimeRange.end)),
            onTap: () => _pickDateTime(false),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Location',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
```

Note: Need to import `AppColors` — add `import 'package:calendar_todo_app/core/theme/app_colors.dart';` at the top.

- [ ] **Step 2: Commit**

```bash
git add lib/ui/pages/event/event_edit_page.dart
git commit -m "feat: add EventEditPage with edit and delete functionality"
```

---

## Task 9: Update Router with Event Routes

**Files:**
- Modify: `lib/core/router/app_router.dart`

- [ ] **Step 1: Update app_router.dart**

Add event creation and edit routes. The router file currently has `/` (home) and `/settings`. Add:

- `/event/new?start=...&end=...` — event creation
- `/event/:id` — event edit (passes CalendaEventAdapter as extra)

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/ui/pages/home/home_page.dart';
import 'package:calendar_todo_app/ui/pages/settings/settings_page.dart';
import 'package:calendar_todo_app/ui/pages/event/event_create_page.dart';
import 'package:calendar_todo_app/ui/pages/event/event_edit_page.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/event/new',
        name: 'eventCreate',
        builder: (context, state) {
          final start = state.uri.queryParameters['start'];
          final end = state.uri.queryParameters['end'];
          return EventCreatePage(
            initialStart: start != null
                ? DateTime.fromMillisecondsSinceEpoch(int.parse(start))
                : DateTime.now(),
            initialEnd: end != null
                ? DateTime.fromMillisecondsSinceEpoch(int.parse(end))
                : DateTime.now().add(const Duration(hours: 1)),
          );
        },
      ),
      GoRoute(
        path: '/event/edit',
        name: 'eventEdit',
        builder: (context, state) {
          final event = state.extra as CalendaEventAdapter;
          return EventEditPage(event: event);
        },
      ),
    ],
  );

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat: add event creation and edit routes to router"
```

---

## Task 10: Update HomePage — Wire Everything Together

**Files:**
- Modify: `lib/ui/pages/home/home_page.dart`

Replace the skeleton HomePage with the real calendar layout.

- [ ] **Step 1: Update HomePage**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:calendar_todo_app/domain/models/calendar_event_adapter.dart';
import 'package:calendar_todo_app/domain/providers/events_provider.dart';
import 'package:calendar_todo_app/ui/widgets/calendar/calendar_section.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    // Watch events for a 2-month window centered on today
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month - 1, 1);
    final rangeEnd = DateTime(now.year, now.month + 2, 1);
    final eventsAsync = ref.watch(
      eventsInDateRangeProvider(DateTimeRange(start: rangeStart, end: rangeEnd)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Todo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (events) {
          final adapters = events
              .map((e) => CalendaEventAdapter.fromDrift(e))
              .toList();

          return CalendarSection(
            events: adapters,
            onEventTapped: (event) {
              context.go('/event/edit', extra: event);
            },
            onTimeSlotTapped: (range) {
              context.go(
                '/event/new?start=${range.start.millisecondsSinceEpoch}'
                '&end=${range.end.millisecondsSinceEpoch}',
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final now = DateTime.now();
          context.go(
            '/event/new?start=${now.millisecondsSinceEpoch}'
            '&end=${now.add(const Duration(hours: 1)).millisecondsSinceEpoch}',
          );
        },
        tooltip: 'New Event',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 2: Run ALL tests**

```bash
flutter test
```

Expected: All tests pass (previous + new calendar UI tests)

- [ ] **Step 3: Verify web build**

```bash
flutter build web --release
```

- [ ] **Step 4: Commit**

```bash
git add lib/ui/pages/home/home_page.dart
git commit -m "feat: wire HomePage with calendar, events, and FAB for event creation"
```

---

## Self-Review

### 1. Spec Coverage Check

| Phase 2 Spec Requirement (Calendar Part) | Task |
|------------------------------------------|------|
| Calendar views (day/week/month) | Task 5 (ViewSwitcher) + Task 6 (CalendarSection) |
| Calendar UI package integration | Task 1 (kalender) + Task 6 |
| Event display in calendar | Task 4 (EventTile) |
| Event creation | Task 7 (EventCreatePage) |
| Event editing | Task 8 (EventEditPage) |
| Event deletion | Task 8 (delete in EventEditPage) |
| Calendar navigation (prev/next/today) | Task 6 |
| Date/time picking | Task 7 + Task 8 |
| Connect to database via Riverpod | Task 3 |
| Event data model bridge | Task 2 |

### 2. Placeholder Scan

No TBD/TODO patterns found. All steps contain complete code.

### 3. Type Consistency

- `CalendaEventAdapter` used consistently across all files
- `CalendarViewMode` enum used in ViewSwitcher and CalendarSection
- Riverpod provider names (`eventsInDateRangeProvider`, `createEventProvider`, `deleteEventProvider`, `calendarsProvider`, `databaseProvider`) used consistently
- `EventsCompanion.insert()` API matches Drift-generated code from Phase 1

### Not in scope (deferred to Plan 3: Todo UI)

- Todo list view
- Todo creation/editing
- Search functionality
- Recurring events UI (RRULE editor)
- Calendar color from calendars table
