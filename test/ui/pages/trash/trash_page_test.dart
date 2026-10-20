import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/trash/trash_page.dart';

void main() {
  testWidgets('DS-020: 回收站左滑永久删除并在确认后真正触发删除', (tester) async {
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
          deletedTodosProvider.overrideWith(
            (ref) => Stream.value([testTodo]),
          ),
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

    // 1. 滑动待办从右向左（DismissDirection.endToStart）
    await tester.drag(find.byKey(const ValueKey('todo-42')), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // 弹窗确认对话框
    expect(find.byType(AlertDialog), findsOneWidget);
    // 点击确认删除按钮（FilledButton）
    await tester.tap(find.widgetWithText(FilledButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(deletedTodoId, 42);

    // 2. 滑动事件从右向左（DismissDirection.endToStart）
    await tester.drag(find.byKey(const ValueKey('event-99')), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(deletedEventId, 99);
  });
}
