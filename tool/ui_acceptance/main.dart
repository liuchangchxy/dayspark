import 'package:dayspark/main.dart' show DaySparkApp;
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/task_allocations_provider.dart';
import 'package:dayspark/infrastructure/platform/notification_service.dart';
import 'package:dayspark_recurrence/dayspark_recurrence.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../test/support/ui_acceptance_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // QA preferences are process-local; native user settings are never touched.
  initializeAcceptancePreferences();
  await NotificationService.ensureTimeZoneInitialized();
  final session = DateTime.now().microsecondsSinceEpoch;
  final db = AppDatabase.forExecutor(
    driftDatabase(
      name: 'dayspark_d_final_acceptance_$session',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  await _seed(container, db);
  runApp(
    UncontrolledProviderScope(container: container, child: const DaySparkApp()),
  );
}

Future<void> _seed(ProviderContainer container, AppDatabase db) async {
  final calendar = await db.calendarsDao.insertCalendar(
    CalendarsCompanion.insert(name: '工作', color: const Value('#2457D6')),
  );
  final now = DateTime.now();
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day, hour, minute);
  final createTodo = container.read(createTodoProvider);
  Future<int> todo(
    String title, {
    DateTime? due,
    int priority = 5,
    String status = 'NEEDS-ACTION',
  }) => createTodo(
    calendarId: calendar,
    summary: title,
    priority: priority,
    status: status,
    dueDate: due,
  );
  await todo(
    '续签 dayspark.dev 域名',
    due: at(18).subtract(const Duration(days: 3)),
    priority: 1,
  );
  await todo(
    '提交差旅报销单',
    due: at(18).subtract(const Duration(days: 2)),
    priority: 3,
  );
  final budget = await todo('提交 Q4 预算表', due: at(18), priority: 1);
  await todo('确认牙医预约', due: at(20));
  await todo('把评审结论同步给设计组', due: at(19), priority: 3);
  await todo('整理 Q4 招聘需求', due: at(18).add(const Duration(days: 2)));
  await todo('预约体检', due: at(18).add(const Duration(days: 3)));
  await todo(
    '长文本验收：整理跨团队协作说明并确认移动端内容保持可读 — Review the international launch checklist and accessibility notes',
  );
  await todo('收集下周发布反馈');
  await todo('回复供应商报价', status: 'COMPLETED');
  final anchor = at(9);
  await createTodo(
    calendarId: calendar,
    summary: '每日站会记录',
    priority: 5,
    status: 'NEEDS-ACTION',
    startDate: anchor,
    dueDate: at(18),
    recurrenceSpec: RecurrenceSpec.parse(
      anchor: RecurrenceAnchor(
        source: RecurrenceAnchorSource.start,
        value: LocalDate(now.year, now.month, now.day),
      ),
      timeZone: 'Asia/Shanghai',
      rrule: 'FREQ=DAILY',
    ),
  );
  final focus = await todo('完成 D Final 交互走查');
  final allocate = container.read(createTaskAllocationProvider);
  await allocate(
    todoId: focus,
    startAt: now.subtract(const Duration(minutes: 20)),
    endAt: now.add(const Duration(minutes: 40)),
  );
  await allocate(todoId: budget, startAt: at(16, 30), endAt: at(17, 30));
  final event = container.read(createEventProvider);
  Future<void> meeting(String title, DateTime start, int minutes) async {
    await event(
      calendarId: calendar,
      summary: title,
      startDt: start,
      endDt: start.add(Duration(minutes: minutes)),
      isAllDay: false,
    );
  }

  await meeting('产品晨会', at(9), 45);
  await meeting('设计评审', at(11, 30), 60);
  await meeting('跨团队项目同步', at(14), 60);
  await meeting('发布准备会', now.add(const Duration(minutes: 30)), 30);

  // Calendar acceptance density: the frozen D Final Calendar shot is a full
  // week with several time slots per day, a multi-day all-day block and
  // deadlines spread across the week. Seed the whole visible week so the
  // high-density layout can be compared against it.
  final weekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  DateTime weekDay(int index, int hour, [int minute = 0]) {
    final day = weekStart.add(Duration(days: index));
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  for (final entry in <int, String>{
    0: '整理周一行动项',
    1: '提交客户回访纪要',
    3: '确认供应商合同条款',
    4: '汇总本周发布指标',
    6: '准备下周计划草稿',
  }.entries) {
    await todo(entry.value, due: weekDay(entry.key, 18));
  }

  await meeting('周会', weekDay(0, 9, 30), 45);
  await meeting('客户回访', weekDay(0, 14), 60);
  await meeting('产品评审', weekDay(1, 10), 90);
  await meeting('一对一沟通', weekDay(1, 16), 30);
  await meeting('深度工作时段', weekDay(2, 9), 120);
  await meeting('供应商会议', weekDay(2, 15), 45);
  await meeting('设计走查', weekDay(3, 11), 45);
  await meeting('周报同步', weekDay(3, 16, 30), 30);
  await meeting('发布准备', weekDay(4, 10), 60);
  await meeting('周复盘', weekDay(4, 15), 60);
  await meeting('家庭安排', weekDay(5, 10), 120);
  await meeting('下周计划', weekDay(6, 19), 45);
  await event(
    calendarId: calendar,
    summary: '设计与研发联合工作坊',
    startDt: weekDay(2, 0),
    endDt: weekDay(4, 0),
    isAllDay: true,
  );

  final planning = await todo('准备 Q4 复盘材料', due: weekDay(4, 18));
  await allocate(
    todoId: budget,
    startAt: weekDay(1, 16, 30),
    endAt: weekDay(1, 17, 30),
  );
  await allocate(
    todoId: budget,
    startAt: weekDay(3, 15),
    endAt: weekDay(3, 16),
  );
  await allocate(todoId: focus, startAt: weekDay(0, 10), endAt: weekDay(0, 11));
  await allocate(
    todoId: focus,
    startAt: weekDay(2, 14),
    endAt: weekDay(2, 15, 30),
  );
  await allocate(
    todoId: planning,
    startAt: weekDay(2, 10),
    endAt: weekDay(2, 11, 30),
  );
}
