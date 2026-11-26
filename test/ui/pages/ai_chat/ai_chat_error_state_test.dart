import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/pages/ai_chat/ai_chat_page.dart';

class _FakeAiChatNotifier extends StateNotifier<List<AiChatMessage>>
    implements AiChatNotifier {
  _FakeAiChatNotifier(super.state);

  int retryCalls = 0;

  @override
  Future<void> retry() async {
    retryCalls++;
  }

  @override
  void clear() {
    state = [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowAiChatNotifier extends StateNotifier<List<AiChatMessage>>
    implements AiChatNotifier {
  _SlowAiChatNotifier(super.state, this.gate);

  final Future<void> gate;

  @override
  Future<void> sendMessage(String message) async {
    state = [...state, AiChatMessage(role: 'user', content: message)];
    await gate;
    state = [...state, AiChatMessage(role: 'assistant', content: 'Done')];
  }

  @override
  void clear() {
    state = [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  required AiChatNotifier notifier,
  bool enabled = true,
  Future<bool> Function(Ref ref)? configured,
}) {
  return ProviderScope(
    overrides: [
      isAiConfiguredProvider.overrideWith(
        configured ?? (ref) async => true,
      ),
      featureFlagsProvider.overrideWith(
        (ref) async => FeatureFlags({FeatureFlag.aiAssistant: enabled}),
      ),
      aiChatProvider.overrideWith((ref) => notifier),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: AiChatPage(),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a failed reply is localized and offers retry', (tester) async {
    final notifier = _FakeAiChatNotifier([
      AiChatMessage(role: 'user', content: 'Plan my week'),
      AiChatMessage(role: 'assistant', content: '', isError: true),
    ]);
    await tester.pumpWidget(_app(notifier: notifier));
    await _settle(tester);

    expect(find.text("The assistant couldn't finish that"), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(notifier.retryCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('config loading shows a spinner instead of a no-key state', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final notifier = _FakeAiChatNotifier([]);
    await tester.pumpWidget(
      _app(
        notifier: notifier,
        configured: (ref) => gate.future,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Connect an AI provider'), findsNothing);

    gate.complete(true);
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('a disabled assistant cannot reach the chat surface', (
    tester,
  ) async {
    final notifier = _FakeAiChatNotifier([]);
    await tester.pumpWidget(
      _app(notifier: notifier, enabled: false),
    );
    await _settle(tester);

    // SPEC 2669: 已关闭 is its own state, with a way back to the switch.
    expect(find.text('The AI assistant is off'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('AI is not configured'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('sending shows an in-thread replying bubble', (tester) async {
    final gate = Completer<void>();
    final notifier = _SlowAiChatNotifier(
      [AiChatMessage(role: 'user', content: 'Plan my week')],
      gate.future,
    );
    await tester.pumpWidget(_app(notifier: notifier));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), 'And tomorrow?');
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up));
    await tester.pump();

    expect(find.text('Replying…'), findsOneWidget);

    gate.complete();
    await _settle(tester);
    expect(find.text('Replying…'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
