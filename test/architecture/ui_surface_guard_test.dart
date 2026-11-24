import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no orphan or duplicate UI pages are resurrected', () {
    final offenders = <String>[];
    for (final path in <String>[
      'lib/ui/pages/about/about_page.dart',
      'lib/ui/pages/calendar/calendars_page.dart',
    ]) {
      if (File(path).existsSync()) offenders.add(path);
    }
    for (final path in <String>['lib/core/router/app_router.dart']) {
      final source = File(path).readAsStringSync();
      for (final route in <String>['/about', '/calendars', '/event/edit']) {
        if (source.contains("'$route'")) offenders.add('$path -> $route');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Orphan pages and routes were deleted in the surface convergence; '
          'see docs/qa/ui-surface-matrix.md 4.1. Offenders: $offenders',
    );
  });

  test('UI does not fall back to the Material dialog family', () {
    final offenders = <String>[];
    final dirs = <String>[
      'lib/ui/pages',
      'lib/ui/widgets',
      'lib/ui/shell',
    ];
    for (final dir in dirs) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final marker in <String>['AlertDialog(', 'SimpleDialog(']) {
          if (source.contains(marker)) offenders.add('${entity.path} -> $marker');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Every confirm/form dialog goes through DsDialog or the shared '
          'confirm dialog; see docs/qa/ui-surface-matrix.md 4.2. '
          'Offenders: $offenders',
    );
  });

  test('toasts go through the shared spec toast', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/ui').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('design/spec_toast.dart')) continue;
      if (entity.path.endsWith('widgets/undo_bar.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('showSnackBar(')) offenders.add(entity.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Message surfaces render through showSpecToast; the undo bar keeps '
          'its own spec geometry. Offenders: $offenders',
    );
  });

  test('the retired palette cannot come back into lib/', () {
    const retired = <String>[
      'FCFCFA',
      '191A17',
      '3F413A',
      'E8E7E1',
      'C2410C',
      '7D5416',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync().toUpperCase();
      for (final hex in retired) {
        if (source.contains(hex)) offenders.add('${entity.path} -> $hex');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'The shared token layer resolves to the frozen spec palette; '
          'see docs/qa/ui-surface-matrix.md 3.7. Offenders: $offenders',
    );
  });

  test('native widgets carry the spec palette, not the retired one', () {
    const retired = <String>[
      'FCFCFA',
      '191A17',
      '3F413A',
      'E8E7E1',
      'C2410C',
      '7D5416',
    ];
    final offenders = <String>[];
    for (final dir in <String>[
      'ios/CalendarTodoWidget',
      'macos/CalendarTodoWidget',
      'android/app/src/main/res',
    ]) {
      final entity = Directory(dir);
      if (!entity.existsSync()) continue;
      for (final file in entity.listSync(recursive: true)) {
        if (file is! File) continue;
        if (!file.path.endsWith('.swift') && !file.path.endsWith('.xml')) {
          continue;
        }
        final source = file.readAsStringSync();
        for (final hex in retired) {
          if (source.toUpperCase().contains(hex)) {
            offenders.add('${file.path} -> $hex');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Widgets use SpecTokens values; see docs/qa/ui-surface-matrix.md '
          '4.2 P12. Offenders: $offenders',
    );
  });

  test('no deleted legacy UI component is resurrected', () {
    const retired = <String>[
      'AboutPage',
      'CalendarsPage',
      'WorkspaceSidebar',
      'SearchEntry',
      'DayStrip',
      'SettingsGroup',
      'TodoListTile',
      'TodosSection',
      'scheduleTodoBlock',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final name in retired) {
        if (RegExp('\\b$name\\b').hasMatch(source)) {
          offenders.add('${entity.path} -> $name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Components deleted in the surface convergence must not come back; '
          'see docs/qa/ui-surface-matrix.md 4.1. Offenders: $offenders',
    );
  });

  test('modal bottom sheets only come from the inventoried hosts', () {
    const allowed = <String>{
      'lib/ui/design/ds.dart',
      'lib/ui/design/spec_components.dart',
      'lib/ui/pages/todo/a2_composer.dart',
      'lib/ui/pages/todo/month_year_picker.dart',
      'lib/ui/widgets/calendar/calendar_slot_sheet.dart',
      'lib/ui/widgets/time_picker/wheel_time_picker.dart',
    };
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (allowed.contains(entity.path)) continue;
      if (entity.readAsStringSync().contains('showModalBottomSheet(')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A new sheet host must first enter the inventory in '
          'docs/qa/ui-surface-matrix.md and this allowlist. '
          'Offenders: $offenders',
    );
  });
}
