import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';
import 'package:dayspark/ui/widgets/schedule/day_strip.dart';
import 'package:dayspark/ui/widgets/todo/date_strip.dart';

Widget _harness(ProviderContainer container, {required bool desktop}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Consumer(
        builder: (context, ref, _) {
          final view = ref.watch(todosViewProvider);
          void onSelect(TodosView next) =>
              ref.read(todosViewProvider.notifier).state = next;
          return Scaffold(
            body: desktop
                ? TodoDesktopToolbar(view: view, onViewSelected: onSelect)
                : DateStrip(view: view, onViewSelected: onSelect),
          );
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  testWidgets('All view offers a Today entry that restores the date strip', (
    tester,
  ) async {
    container.read(todosViewProvider.notifier).state = const TodosAllView();
    await tester.pumpWidget(_harness(container, desktop: false));
    await tester.pump();

    expect(find.byKey(const ValueKey('date-strip-week')), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pump();

    final view = container.read(todosViewProvider);
    expect(view, isA<TodosDayView>());
    expect((view as TodosDayView).day, today);
    expect(find.byKey(const ValueKey('date-strip-week')), findsOneWidget);
  });

  testWidgets('Unplanned view offers a Today entry that restores the strip', (
    tester,
  ) async {
    container.read(todosViewProvider.notifier).state = const TodosInboxView();
    await tester.pumpWidget(_harness(container, desktop: false));
    await tester.pump();

    expect(find.byKey(const ValueKey('date-strip-week')), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pump();

    final view = container.read(todosViewProvider);
    expect(view, isA<TodosDayView>());
    expect((view as TodosDayView).day, today);
    expect(find.byKey(const ValueKey('date-strip-week')), findsOneWidget);
  });

  testWidgets('date view still browses other dates', (tester) async {
    container.read(todosViewProvider.notifier).state = TodosDayView(today);
    await tester.pumpWidget(_harness(container, desktop: false));
    await tester.pump();

    final target = today.add(const Duration(days: 3));
    await tester.tap(find.byKey(ValueKey(DayStrip.dayKey(target))));
    await tester.pump();

    final view = container.read(todosViewProvider) as TodosDayView;
    expect(view.day.isAtSameMomentAs(target), isTrue);
  });

  testWidgets('desktop toolbar offers the same Today entry from All', (
    tester,
  ) async {
    container.read(todosViewProvider.notifier).state = const TodosAllView();
    await tester.pumpWidget(_harness(container, desktop: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('date-strip-week')), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pump();

    final view = container.read(todosViewProvider);
    expect(view, isA<TodosDayView>());
    expect((view as TodosDayView).day, today);
    expect(find.byKey(const ValueKey('date-strip-week')), findsOneWidget);
  });
}
