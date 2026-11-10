import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/ui/shell/workspace_sidebar.dart';

/// Below this width the app uses the phone chrome (top bar + bottom tabs).
/// Above it the desktop workspace appears; between 760 and 980 the rail folds
/// to its 64px icon form, exactly as the desktop prototype does.
const double kWorkspaceBreakpoint = 760;

bool isWorkspaceLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWorkspaceBreakpoint;

class WorkspaceScaffold extends ConsumerWidget {
  const WorkspaceScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isWorkspaceLayout(context)) return child;
    // The rail prints "Ctrl K" on its search row; a hint nobody bound is a
    // promise the app breaks the first time someone presses it.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          final router = GoRouter.maybeOf(context);
          if (router == null) return;
          if (router.routerDelegate.currentConfiguration.uri.path == '/search') {
            return;
          }
          router.go('/search');
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WorkspaceSidebar(),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
