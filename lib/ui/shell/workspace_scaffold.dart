import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/ui/shell/workspace_sidebar.dart';

/// Width at which the workspace rail appears. One constant so the shell and
/// every page's own layout branch on the same number.
const double kWorkspaceBreakpoint = 1000;

bool isWorkspaceLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWorkspaceBreakpoint;

/// Desktop chrome for the whole app.
///
/// It sits above the router, so pushing Settings, Search or a detail page no
/// longer swaps the workspace for a standalone phone-style page with its own
/// back button — the rail stays put and only the content pane changes.
class WorkspaceScaffold extends ConsumerWidget {
  const WorkspaceScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isWorkspaceLayout(context)) return child;
    return Scaffold(
      body: Row(
        children: [
          const WorkspaceSidebar(),
          Expanded(
            child: Column(
              children: [
                const SizedBox(
                  height: 2,
                  child: ColoredBox(
                    color: AppColors.brandWarm,
                    child: SizedBox.expand(),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
