import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';

import 'l10n/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/platform_scroll_behavior.dart';
import 'domain/providers/home_widget_provider.dart';
import 'domain/providers/sync_client_provider.dart' show syncRuntimeProvider;
import 'domain/providers/theme_provider.dart' show themeModeProvider, themeColorProvider;
import 'domain/providers/locale_provider.dart';
import 'infrastructure/platform/alarm_service.dart';
import 'infrastructure/platform/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must run before the first saveWidgetData: Apple widgets read
  // UserDefaults(suiteName:) — without this the host app writes to the
  // wrong defaults and iOS/macOS widgets stay empty. Apple-only call.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await HomeWidget.setAppGroupId('group.com.dayspark.app');
  }
  await AlarmService.init();
  // tz database + local location must be ready before any reminder can
  // schedule (initializeDatabase resets tz.local to UTC if run later).
  await NotificationService.ensureTimeZoneInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };

  runApp(const ProviderScope(child: DaySparkApp()));
}

class DaySparkApp extends ConsumerWidget {
  const DaySparkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One-shot read: starts the write-driven widget refresh listener for
    // the app's lifetime (provider instance is cached by the container).
    ref.read(homeWidgetAutoRefreshProvider);
    // Sync engine (outbox drain + SSE + connectivity triggers); no-op
    // until a server base URL and tokens are configured.
    ref.read(syncRuntimeProvider);
    ref.watch(localeProvider);
    ref.read(localeProvider.notifier).load();
    final themeMode = ref.watch(themeModeProvider);
    final seedColor = ref.watch(themeColorProvider);
    final locale = ref.watch(localeProvider);
    return ScrollConfiguration(
      behavior: AppScrollBehavior(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            final router = AppRouter.router;
            if (router.canPop()) router.pop();
          },
        },
        child: Focus(
          autofocus: true,
          child: MaterialApp.router(
            title: 'DaySpark',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(seedColor: seedColor),
            darkTheme: AppTheme.dark(seedColor: seedColor),
            themeMode: themeMode,
            locale: locale,
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: AppRouter.router,
          ),
        ),
      ),
    );
  }
}
