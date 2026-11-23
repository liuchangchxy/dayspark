import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/pages/tags/tags_page.dart';

void main() {
  testWidgets('TagsPage displays tags with combined todo and event counts',
      (tester) async {
    const testTag = Tag(id: 7, name: 'Work', color: '#4F7BBF', serverRev: 0);
    final testTodo = Todo(
      id: 10,
      summary: 'Task 1',
      calendarId: 1,
      status: 'NEEDS_ACTION',
      priority: 0,
      percentComplete: 0,
      recurrenceRevision: 0,
      sortOrder: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      serverRev: 0,
    );
    final testEvent = Event(
      id: 20,
      calendarId: 1,
      summary: 'Meeting 1',
      startDt: DateTime.now(),
      endDt: DateTime.now().add(const Duration(hours: 1)),
      isAllDay: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      serverRev: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tagsProvider.overrideWith((ref) => Stream.value([testTag])),
          allTodosProvider.overrideWith((ref) => Stream.value([testTodo])),
          todoTagIdsMapProvider
              .overrideWith((ref) => Stream.value({10: {7}})),
          allEventsProvider.overrideWith((ref) => Stream.value([testEvent])),
          eventTagIdsMapProvider
              .overrideWith((ref) => Stream.value({20: {7}})),
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
          home: Scaffold(body: TagsPage(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    // Count should be 2 (1 todo + 1 event)
    expect(find.text('2 项'), findsOneWidget);

    // Clicking "+ 创建标签" navigates to in-place subpage without opening sheet
    await tester.tap(find.widgetWithText(DsButton, '创建标签'));
    await tester.pumpAndSettle();

    // Verify in-place subpage content
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('标签名称'), findsOneWidget);
    expect(find.text('颜色'), findsOneWidget);

    // Cancel returns to list
    await tester.tap(find.widgetWithText(DsButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);

    // Clicking existing tag row enters edit subpage
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(find.text('编辑标签'), findsOneWidget);
    expect(find.widgetWithText(DsButton, '删除标签 (2)'), findsOneWidget);

    // Tap delete button to open confirmation dialog
    await tester.tap(find.widgetWithText(DsButton, '删除标签 (2)'));
    await tester.pumpAndSettle();

    expect(find.byType(DsDialog), findsOneWidget);
    expect(find.textContaining('2 项'), findsOneWidget);
  });
}
