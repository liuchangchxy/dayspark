import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/models/calendar_event_adapter.dart';
import 'package:dayspark/domain/providers/attachments_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/domain/services/attachment_files.dart';
import 'package:dayspark/domain/services/attachment_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/event/event_form_page.dart';
import 'package:dayspark/ui/pages/todo/todo_form_page.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Save means "the bundle I was just looking at", not "as much of it as the
/// database would take". The form used to write the row, then each association
/// in turn, swallowing every failure and leaving anyway — so a title that
/// landed with an attachment that did not looked like a successful save.
(GoRouter, Widget) _app(AppDatabase db, {Todo? todo, CalendaEventAdapter? event, List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('list'))),
      GoRoute(
        path: '/todo/edit',
        builder: (_, __) => TodoFormPage(todo: todo),
      ),
      GoRoute(
        path: '/event/new',
        builder: (_, __) => EventFormPage(
          event: event,
          initialStart: DateTime(2026, 11, 1, 9),
          initialEnd: DateTime(2026, 11, 1, 10),
        ),
      ),
    ],
  );
  return (
    router,
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), ...overrides],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// A reminder write that always fails — standing in for anything that can go
/// wrong late in a draft, which is exactly where the old code gave up.
Override _failingReminderWrites() => createReminderProvider.overrideWith(
  (ref) =>
      ({
        required parentType,
        required parentId,
        required triggerTime,
      }) async => throw StateError('reminder write refused'),
);

/// The system picker, replaced so a test can hand the form a file without a
/// real one. Nothing else in this file opens a picker.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);

  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => result;
}

/// A file store that keeps bodies in memory.
///
/// WHY not a temp directory: `testWidgets` runs its body in a fake-async zone
/// where a real disk write never completes, so the save this test is about
/// would hang inside the transaction instead of finishing. [written] records
/// every body the store was asked to hold and is never pruned, so a test can
/// tell "nothing was ever staged" apart from "it was staged and cleaned up".
class _MemoryFileStore extends AttachmentFileStore {
  final List<String> written = <String>[];
  final Map<String, List<int>> live = <String, List<int>>{};

  @override
  Future<String> write({
    required String key,
    required String fileName,
    required List<int> bytes,
  }) async {
    final path = pathFor(key: key, fileName: fileName);
    written.add(path);
    live[path] = bytes;
    return path;
  }

  @override
  Future<void> delete(String? path) async {
    if (path != null) live.remove(path);
  }
}

/// Stages two attachments in a form whose second row write is refused, and
/// returns the store the form was given so the caller can see what survived.
///
/// Two attachments, with only the second refused, on purpose: that puts the
/// failure *after* the first file is already written, which is the only point
/// at which there is anything to clean up.
Future<_MemoryFileStore> _driveFailingSave(
  WidgetTester tester,
  AppDatabase db, {
  required String route,
}) async {
  final store = _MemoryFileStore();
  final service = AttachmentService(
    db: db,
    api: const LocalOnlyAttachmentApi(),
    files: store,
  );
  var inserts = 0;
  FilePicker.platform = _FakeFilePicker(
    FilePickerResult([
      PlatformFile(
        name: 'report.txt',
        size: 12,
        bytes: Uint8List.fromList(utf8.encode('report body')),
      ),
    ]),
  );

  final (router, app) = _app(
    db,
    overrides: [
      attachmentServiceProvider.overrideWithValue(service),
      insertAttachmentRowProvider.overrideWith(
        (ref) =>
            (
              tx, {
              required parentType,
              required parentId,
              required fileName,
              mimeType,
              required data,
              required onFileWritten,
            }) async {
              inserts++;
              if (inserts == 2) {
                throw StateError('second attachment refused');
              }
              return service.insertRow(
                tx,
                parentType: parentType,
                parentId: parentId,
                fileName: fileName,
                mimeType: mimeType,
                data: data,
                onFileWritten: onFileWritten,
              );
            },
      ),
    ],
  );
  await tester.pumpWidget(app);
  await _settle(tester);
  router.push(route);
  await _settle(tester);

  await tester.enterText(find.byType(TextField).first, 'Ship the report');
  await tester.pump();
  for (var i = 0; i < 2; i++) {
    final add = find.text('Add attachment');
    await tester.ensureVisible(add);
    await tester.pump();
    await tester.tap(add);
    await _settle(tester);
  }
  expect(
    find.text('report.txt'),
    findsNWidgets(2),
    reason: 'both files are staged in the draft before anything is written',
  );
  expect(store.written, isEmpty, reason: 'staging alone writes nothing');

  await tester.tap(find.text('Save'));
  await _settle(tester);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  setUp(() async {
    // forTesting seeds one calendar already; a second would make the
    // "which calendar?" step appear in tests that are not about it.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('a failing late write takes the whole edit down with it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calendarId = (await db.select(db.calendars).get()).single.id;
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Original title',
            dueDate: Value(DateTime(2026, 10, 30, 18)),
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    final (router, app) = _app(
      db,
      todo: todo,
      overrides: [_failingReminderWrites()],
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/todo/edit');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Renamed by the user');
    await tester.pump();

    // Add a reminder so the commit has a failing write after the row itself.
    // Stage a reminder: the sheet is where the choice is made, and until it
    // is made the draft has nothing extra to write.
    await tester.tap(find.text('Add Reminder'));
    await _settle(tester);
    await tester.tap(find.text('On time'));
    await _settle(tester);
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'the reminder is staged and the sheet is gone',
    );

    await tester.tap(find.text('Save'));
    await _settle(tester);

    final after = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(
      after.summary,
      'Original title',
      reason: 'the title must not land if the rest of the draft did not',
    );
    expect(
      find.byType(TodoFormPage),
      findsOneWidget,
      reason: 'the form stays open so the user can retry or fix the draft',
    );
    expect(find.text('list'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a clean save still writes the whole edit', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calendarId = (await db.select(db.calendars).get()).single.id;
    final id = await db
        .into(db.todos)
        .insert(
          TodosCompanion.insert(
            calendarId: calendarId,
            summary: 'Original title',
          ),
        );
    final todo = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();

    final (router, app) = _app(db, todo: todo);
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/todo/edit');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final after = await (db.select(
      db.todos,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(after.summary, 'Renamed');
    expect(after.id, id, reason: 'an edit updates in place');
    expect((await db.select(db.todos).get()), hasLength(1));
    expect(find.byType(TodoFormPage), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a failing late write does not create a partial event', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (router, app) = _app(
      db,
      overrides: [_failingReminderWrites()],
    );
    await tester.pumpWidget(app);
    await _settle(tester);
    router.push('/event/new');
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Team offsite');
    await tester.pump();
    await tester.tap(find.text('Add Reminder'));
    await _settle(tester);
    await tester.tap(find.text('On time'));
    await _settle(tester);

    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(
      await db.select(db.events).get(),
      isEmpty,
      reason: 'a half-written event is worse than none',
    );
    expect(find.byType(EventFormPage), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a rolled-back todo draft leaves no staged file behind', (
    tester,
  ) async {
    // The rollback takes the row but cannot take the bytes: the file was
    // written before the write that failed. Left behind it is an orphan that
    // SQLite may hand the next insert's id to, and that row would adopt it as
    // its own attachment.
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = await _driveFailingSave(tester, db, route: '/todo/edit');

    expect(
      store.written,
      hasLength(1),
      reason: 'the transaction really did write a file before it failed',
    );
    expect(
      await db.select(db.todos).get(),
      isEmpty,
      reason: 'the row went with the rollback',
    );
    expect(
      await db.select(db.attachments).get(),
      isEmpty,
      reason: 'neither attachment row survived',
    );
    expect(
      store.live,
      isEmpty,
      reason: 'the file the transaction wrote is not left as an orphan',
    );
    expect(find.byType(TodoFormPage), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a rolled-back event draft leaves no staged file behind', (
    tester,
  ) async {
    // The event form carries the same cleanup as the todo form, in code that
    // looks identical — which is exactly how one of them ends up without it.
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = await _driveFailingSave(tester, db, route: '/event/new');

    expect(store.written, hasLength(1));
    expect(
      await db.select(db.events).get(),
      isEmpty,
      reason: 'the row went with the rollback',
    );
    expect(await db.select(db.attachments).get(), isEmpty);
    expect(store.live, isEmpty);
    expect(find.byType(EventFormPage), findsOneWidget);
    await _unmount(tester);
  });
}
