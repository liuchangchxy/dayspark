import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_page.dart';

class _GuardedPage extends StatelessWidget {
  const _GuardedPage({required this.vetoes});

  final ValueNotifier<int> vetoes;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) vetoes.value++;
      },
      child: const WorkspacePage(
        title: 'Form',
        child: Text('form-body', key: ValueKey('form-body')),
      ),
    );
  }
}

GoRouter _router(ValueNotifier<int> vetoes) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: Text('home')),
    ),
    GoRoute(
      path: '/form',
      builder: (_, __) => _GuardedPage(vetoes: vetoes),
    ),
  ],
);

Widget _app(GoRouter router) => MaterialApp.router(
  routerConfig: router,
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the back arrow asks the route before leaving', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final vetoes = ValueNotifier<int>(0);
    addTearDown(vetoes.dispose);
    final router = _router(vetoes);
    await tester.pumpWidget(_app(router));
    await _settle(tester);

    router.push('/form');
    await _settle(tester);
    expect(find.byKey(const ValueKey('form-body')), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);

    expect(vetoes.value, 1);
    expect(find.byKey(const ValueKey('form-body')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
