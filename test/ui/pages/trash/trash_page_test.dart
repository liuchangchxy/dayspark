import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

void main() {
  testWidgets('DS-020: 回收站逐条永久删除并在确认后真正触发删除', (tester) async {
    int? deletedTodoId;
    int? deletedEventId;

    final testTodo = Todo(
      id: 42,
      summary: '测试废弃待办',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    final testEvent = Event(
      id: 99,
      calendarId: 1,
      summary: '测试废弃事件',
      startDt: DateTime.now(),
      endDt: DateTime.now().add(const Duration(hours: 1)),
      isAllDay: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deletedTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          deletedEventsProvider.overrideWith(
            (ref) => Stream.value([testEvent]),
          ),
          permanentDeleteTodoProvider.overrideWithValue((id) async {
            deletedTodoId = id;
          }),
          hardDeleteEventWithChildrenProvider.overrideWithValue((id) async {
            deletedEventId = id;
          }),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrashPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('测试废弃待办'), findsOneWidget);
    expect(find.text('测试废弃事件'), findsOneWidget);

    // 1. 每行自带的删除按钮（不再用左滑：桌面上一次误拖就是不可逆删除）
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('trash-todo-42')),
        matching: find.byIcon(CupertinoIcons.delete),
      ),
    );
    await tester.pumpAndSettle();

    // 弹窗确认对话框
    expect(find.byType(DsDialog), findsOneWidget);
    // 点击确认删除按钮（DsButton）
    await tester.tap(find.widgetWithText(DsButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(deletedTodoId, 42);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('trash-event-99')),
        matching: find.byIcon(CupertinoIcons.delete),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DsDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(DsButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(deletedEventId, 99);
  });

  testWidgets('a failed restore reports the error and re-enables the row', (
    tester,
  ) async {
    final testTodo = Todo(
      id: 42,
      summary: '测试废弃待办',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deletedTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          deletedEventsProvider.overrideWith((ref) => Stream.value([])),
          restoreTodoProvider.overrideWithValue(
            (id) async => throw Exception('restore failed'),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrashPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DsButton, '恢复'));
    await tester.pumpAndSettle();

    expect(find.text('出错了，请重试。'), findsOneWidget);
    final restoreButton = tester.widget<DsButton>(
      find.widgetWithText(DsButton, '恢复'),
    );
    expect(
      restoreButton.onPressed,
      isNotNull,
      reason: 'a failed restore must not leave the button dead',
    );
  });

  testWidgets('empty-trash confirmation includes the item count', (
    tester,
  ) async {
    final testTodo = Todo(
      id: 42,
      summary: '测试废弃待办',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );
    final testEvent = Event(
      id: 99,
      calendarId: 1,
      summary: '测试废弃事件',
      startDt: DateTime.now(),
      endDt: DateTime.now().add(const Duration(hours: 1)),
      isAllDay: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deletedTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          deletedEventsProvider.overrideWith(
            (ref) => Stream.value([testEvent]),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrashPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DsButton, '清空回收站'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 项'), findsOneWidget);
  });

  testWidgets('a successful restore reports the restored banner', (
    tester,
  ) async {
    final testTodo = Todo(
      id: 42,
      summary: '测试废弃待办',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deletedTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          deletedEventsProvider.overrideWith((ref) => Stream.value([])),
          restoreTodoProvider.overrideWithValue((id) async {}),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrashPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DsButton, '恢复'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已恢复「测试废弃待办」'), findsOneWidget);
  });

  testWidgets('a permanent delete reports the deleted banner', (tester) async {
    final testTodo = Todo(
      id: 42,
      summary: '测试废弃待办',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deletedTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          deletedEventsProvider.overrideWith((ref) => Stream.value([])),
          permanentDeleteTodoProvider.overrideWithValue((id) async {}),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrashPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('trash-todo-42')),
        matching: find.byIcon(CupertinoIcons.delete),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DsButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已永久删除「测试废弃待办」'), findsOneWidget);
  });

  testWidgets('emptying the trash reports the cleared banner', (tester) async {
    final testTodo = Todo(
      id: 42,
      summary: '测试废弃待办',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deletedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deletedTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          deletedEventsProvider.overrideWith((ref) => Stream.value([])),
          emptyTrashProvider.overrideWithValue(() async {}),
          emptyEventTrashProvider.overrideWithValue(() async {}),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TrashPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DsButton, '清空回收站'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DsDialog),
        matching: find.widgetWithText(DsButton, '清空回收站'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('回收站已清空'), findsOneWidget);
  });
}
