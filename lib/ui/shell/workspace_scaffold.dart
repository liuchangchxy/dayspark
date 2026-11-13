import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';

/// Below this width the app uses the phone chrome (top bar + bottom tabs).
/// Above it the Direction C shell appears: one 56px bar across the top.
///
/// The threshold is where the desktop frame stops being squeezed: the timeline
/// plus its 356px panel need roughly a thousand pixels before either has to
/// give something up, and a half-screen window reads better with the tab bar.
const double kWorkspaceBreakpoint = 1000;

bool isWorkspaceLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWorkspaceBreakpoint;

/// Desktop chrome for every destination: a single top bar, then the page.
///
/// There is no sidebar. Navigation lives in the bar's day/week/month switch and
/// in the destinations the pages themselves put in front of you, so the
/// timeline keeps the full width it needs.
class WorkspaceScaffold extends ConsumerWidget {
  const WorkspaceScaffold({super.key, required this.child, this.clock});

  final Widget child;

  /// The clock the bar prints. Pages that own a clock hand it down so the bar
  /// and the timeline agree.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isWorkspaceLayout(context)) return child;
    // The bar prints no shortcut hint, but Ctrl K is the habit the old rail
    // taught; keep it bound so it never silently stops working.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          final router = GoRouter.maybeOf(context);
          if (router == null) return;
          if (router.routerDelegate.currentConfiguration.uri.path == '/search') {
            return;
          }
          router.push('/search');
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: context.ds.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SparkTopBar(clock: clock),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
