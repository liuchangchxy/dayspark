import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';

class _Opener extends ConsumerWidget {
  const _Opener();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: DsButton(
          label: 'open',
          onPressed: () => showAiConfigDialog(context, ref),
        ),
      ),
    );
  }
}

Widget _app({
  required ValidateAiKey validate,
  required void Function() onSave,
}) =>
    ProviderScope(
      overrides: [
        aiConfigProvider.overrideWith((ref) async => null),
        validateAiKeyProvider.overrideWithValue(validate),
        saveAiConfigProvider.overrideWithValue((
          {required String apiKey, required String baseUrl, required String model}
        ) async {
          onSave();
        }),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: _Opener(),
      ),
    );

Future<void> _enterKeyAndSave(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  final keyField = find.descendant(
    of: find.widgetWithText(DsField, 'API Key'),
    matching: find.byType(TextField),
  );
  await tester.enterText(keyField, 'sk-bad-key');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a 401 blocks the save and says so', (tester) async {
    var saved = false;
    await tester.pumpWidget(
      _app(
        validate: ({required baseUrl, required apiKey}) async =>
            const AiKeyCheck(statusCode: 401),
        onSave: () => saved = true,
      ),
    );

    await _enterKeyAndSave(tester);

    // SPEC 2436: exact copy, and the dialog stays open so the key can be
    // corrected instead of being stored unvalidated.
    expect(find.text('Key check failed.'), findsOneWidget);
    expect(
      find.text('The server returned 401; this change was not saved.'),
      findsOneWidget,
    );
    expect(saved, isFalse);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('a non-401 failure gets an honest reason and is not saved', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      _app(
        validate: ({required baseUrl, required apiKey}) async =>
            const AiKeyCheck(error: 'connectionTimeout'),
        onSave: () => saved = true,
      ),
    );

    await _enterKeyAndSave(tester);

    expect(
      find.text(
        'The provider request failed (connectionTimeout); '
        'this change was not saved.',
      ),
      findsOneWidget,
    );
    expect(saved, isFalse);
  });

  testWidgets('provider chips are inline and Base URL is always editable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        validate: ({required baseUrl, required apiKey}) async =>
            const AiKeyCheck(statusCode: 200),
        onSave: () {},
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    final urlField = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(DsField, 'Base URL'),
        matching: find.byType(TextField),
      ),
    );
    expect(urlField.enabled, isTrue);
  });
}
