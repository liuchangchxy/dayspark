import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'l10n/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/platform_target.dart';
import 'core/utils/platform_scroll_behavior.dart';
import 'domain/providers/home_widget_provider.dart';
import 'domain/providers/database_provider.dart';
import 'domain/providers/default_calendar_provider.dart';
import 'domain/providers/record_bus_provider.dart';
import 'domain/providers/sync_client_provider.dart'
    show deviceRegistrationProvider, syncRuntimeProvider;
import 'domain/providers/theme_provider.dart' show themeColorProvider;
import 'domain/providers/locale_provider.dart';
import 'infrastructure/platform/alarm_service.dart';
import 'infrastructure/platform/home_widget_interactivity.dart';
import 'infrastructure/platform/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };

  await _start();
}

/// Runs launch initialization and, if any step throws, replaces the (still
/// blank) window with a diagnostics page instead of leaving a white screen.
///
/// The retry entry point is this function itself: it re-runs every step on a
/// fresh provider container.
Future<void> _start() async {
  ProviderContainer? container;
  try {
    await _preparePlatform();

    container = ProviderContainer();
    // Load the stored default calendar before the first write can read the
    // provider, so a capture at launch does not fall back to the first
    // calendar.
    await container.read(defaultCalendarIdProvider.notifier).ensureLoaded();
    final database = container.read(databaseShutdownProvider);
    late final AppLifecycleListener exitListener;
    exitListener = AppLifecycleListener(
      onExitRequested: () async {
        // Stop every provider before closing: no new queries can start, and
        // the awaited close lets the database isolate finish
        // sqlite3_close_v2 (and its FFI callbacks) before the process exits.
        container?.dispose();
        await database.close();
        exitListener.dispose();
        return AppExitResponse.exit;
      },
    );
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const DaySparkApp(),
      ),
    );
    // The plugin's restore pass is O(saved alarms) platform round-trips
    // (0.64-0.80 s with 12). Schedulers await the same future, so starting it
    // after the first frame removes the startup stall without dropping alarms.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AlarmService.init());
    });
  } catch (error, stack) {
    debugPrint('startup failed: $error\n$stack');
    final failed = container;
    container = null;
    try {
      failed?.dispose();
    } catch (closeError) {
      debugPrint('startup: failed to dispose container: $closeError');
    }
    runApp(_StartupFailureApp(description: '$error', stack: '$stack'));
  }
}

Future<void> _preparePlatform() async {
  // Must run before the first saveWidgetData: iOS/macOS widgets read
  // UserDefaults(suiteName:) — without this the host app writes to the
  // wrong defaults and widgets stay empty. home_widget supports iOS here;
  // macOS goes through the Runner method-channel shim.
  if (isIOS || isMacOS) {
    try {
      await HomeWidget.setAppGroupId('group.com.dayspark.app');
    } catch (e) {
      debugPrint('home_widget: setAppGroupId error: $e');
    }
  }
  // Widget-button taps reach Dart through the interactivity callback
  // (T3 wires native buttons to `dayspark://` URIs). Only Android/iOS have
  // a supported home_widget implementation.
  if (supportsHomeWidget) {
    try {
      await HomeWidget.registerInteractivityCallback(
        widgetInteractivityCallback,
      );
    } catch (e) {
      debugPrint('home_widget: registerInteractivityCallback error: $e');
    }
  }
  // tz database + local location must be ready before any reminder can
  // schedule (initializeDatabase resets tz.local to UTC if run later).
  await NotificationService.ensureTimeZoneInitialized();
}

/// Minimal app shell for the pre-container failure: no providers, no router,
/// just localization around one page. Retry calls [_start] again so the whole
/// initialization (including the database) is re-run.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.description, required this.stack});

  final String description;
  final String stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DaySpark',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: _StartupFailurePage(
        diagnostics: 'DaySpark startup failure\n\n$description\n\n$stack',
        onRetry: _start,
      ),
    );
  }
}

class _StartupFailurePage extends StatefulWidget {
  const _StartupFailurePage({required this.diagnostics, required this.onRetry});

  final String diagnostics;
  final Future<void> Function() onRetry;

  @override
  State<_StartupFailurePage> createState() => _StartupFailurePageState();
}

class _StartupFailurePageState extends State<_StartupFailurePage> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await widget.onRetry();
    // A successful retry replaces this tree; if it failed, the failure app is
    // run again and this state is gone too. Reaching here means the retry
    // returned without either, so let the button be usable again.
    if (mounted) setState(() => _retrying = false);
  }

  Future<void> _exportDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: widget.diagnostics));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l?.feedbackCopied ?? 'Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 32,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l?.startupFailedTitle ?? "DaySpark couldn't open",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l?.startupFailedBody ??
                        'The local database did not open. Your data is still '
                            'on disk.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey('startup-retry'),
                    onPressed: _retrying ? null : _retry,
                    child: _retrying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l?.retry ?? 'Retry'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('startup-export-diagnostics'),
                    onPressed: _exportDiagnostics,
                    child: Text(l?.exportDiagnostics ?? 'Export diagnostics'),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      widget.diagnostics,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DaySparkApp extends ConsumerWidget {
  const DaySparkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One-shot read: starts the write-driven widget refresh listener for
    // the app's lifetime (provider instance is cached by the container).
    ref.read(homeWidgetAutoRefreshProvider);
    // Same lifetime, same driver: the record bus reconciles reminder
    // notifications against each committed write (cold-start sweep included).
    ref.read(reminderReconcilerProvider);
    // Sync engine (outbox drain + SSE + connectivity triggers); no-op
    // until a server base URL and tokens are configured.
    ref.read(syncRuntimeProvider);
    // Device registration rides the same lifetime: reports this install once
    // it is logged in, so the account's device list is populated even for
    // installs that signed in before this feature existed.
    ref.watch(deviceRegistrationProvider);
    // The frozen spec defines only the light paper theme (settings > theme: 浅色),
    // so the app must not follow the system into a dark palette.
    final accent = ref.watch(themeColorProvider);
    final locale = ref.watch(localeProvider);
    return ScrollConfiguration(
      behavior: AppScrollBehavior(),
      // Escape is not bound app-wide: a page that has unsaved work owns its
      // own escape handling, so the key cannot pop a form past its discard
      // confirmation.
      child: MaterialApp.router(
        title: 'DaySpark',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(accent: accent.light),
        darkTheme: AppTheme.dark(accent: accent.dark),
        themeMode: ThemeMode.light,
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
    );
  }
}
