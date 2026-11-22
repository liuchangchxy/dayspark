import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';

const double kWorkspaceBreakpoint = 720;

bool isWorkspaceLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWorkspaceBreakpoint;

/// Desktop chrome for every destination: a single top bar, then the page.
class WorkspaceScaffold extends ConsumerWidget {
  const WorkspaceScaffold({super.key, required this.child, this.clock});

  final Widget child;

  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isWorkspaceLayout(context)) return child;
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
          backgroundColor: SpecTokens.paper,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SparkTopBar(clock: clock),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
