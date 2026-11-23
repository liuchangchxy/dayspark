import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/ui/pages/search/search_page.dart';
import 'package:dayspark/ui/shell/spark_top_bar.dart';
import 'package:dayspark/ui/shell/sync_status_banner.dart';

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
          showCommandOverlay(context);
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          showCommandOverlay(context);
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
              const SyncStatusBanner(),
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
