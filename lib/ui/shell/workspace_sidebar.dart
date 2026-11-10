import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/feature_flags_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

/// Desktop workspace rail matching DESIGN.md 6 and VISUAL_POLISH.md:
/// Width 236px (or 64px compact icon rail under 980px),
/// 32px line-height, neutral selection (`surface-2` / `sidebarSelected`),
/// refined ink mark.
class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({super.key});

  static const double width = 236;
  static const double compactWidth = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final isHome = currentPath(context) == '/';
    final tab = isHome ? ref.watch(workspaceTabProvider) : null;
    final view = ref.watch(todosViewProvider);
    final showAi =
        ref.watch(featureFlagsProvider).valueOrNull?.isEnabled(FeatureFlag.aiAssistant) ?? true;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 980;

    return Material(
      color: AppColors.sidebar,
      child: SizedBox(
        width: isCompact ? compactWidth : width,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? AppSpacing.xs : AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorkspaceHeader(compact: isCompact),
                const SizedBox(height: AppSpacing.md),
                SearchEntry(
                  compact: isCompact,
                  onTap: () => _goDestination(context, '/search'),
                ),
                const SizedBox(height: AppSpacing.lg),
                _NavigationItem(
                  compact: isCompact,
                  label: l.today,
                  icon: CupertinoIcons.bolt,
                  selected: tab == AppTab.action,
                  onTap: () => _goTab(context, ref, AppTab.action),
                ),
                _NavigationItem(
                  compact: isCompact,
                  label: l.calendar,
                  icon: CupertinoIcons.calendar,
                  selected: tab == AppTab.calendar,
                  onTap: () => _goTab(context, ref, AppTab.calendar),
                ),
                _NavigationItem(
                  compact: isCompact,
                  label: l.todos,
                  icon: CupertinoIcons.checkmark_rectangle,
                  selected: tab == AppTab.todos,
                  onTap: () => _goTab(context, ref, AppTab.todos),
                ),
                if (!isCompact) ...[
                  _SubNavigationItem(
                    label: l.unplannedView,
                    selected: tab == AppTab.todos && view is TodosInboxView,
                    onTap: () => _goTodosView(context, ref, const TodosInboxView()),
                  ),
                  _SubNavigationItem(
                    label: l.allTodosView,
                    selected: tab == AppTab.todos && view is TodosAllView,
                    onTap: () => _goTodosView(context, ref, const TodosAllView()),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.sidebarSelected,
                ),
                const SizedBox(height: AppSpacing.md),
                if (!isCompact) ...[
                  _NavigationItem(
                    compact: false,
                    label: l.manageCalendars,
                    icon: CupertinoIcons.calendar,
                    selected: _locationIs(context, '/calendars'),
                    onTap: () => _goDestination(context, '/calendars'),
                  ),
                  _NavigationItem(
                    compact: false,
                    label: l.manageTags,
                    icon: CupertinoIcons.tag,
                    selected: _locationIs(context, '/tags'),
                    onTap: () => _goDestination(context, '/tags'),
                  ),
                  _NavigationItem(
                    compact: false,
                    label: l.trash,
                    icon: CupertinoIcons.trash,
                    selected: _locationIs(context, '/trash'),
                    onTap: () => _goDestination(context, '/trash'),
                  ),
                ],
                if (showAi)
                  _NavigationItem(
                    compact: isCompact,
                    label: l.aiAssistant,
                    icon: CupertinoIcons.sparkles,
                    selected: _locationIs(context, '/ai-chat'),
                    onTap: () => _goDestination(context, '/ai-chat'),
                  ),
                const Spacer(),
                _NavigationItem(
                  compact: isCompact,
                  label: l.settings,
                  icon: CupertinoIcons.settings,
                  selected: _locationIs(context, '/settings'),
                  onTap: () => _goDestination(context, '/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String currentPath(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      final router = GoRouter.maybeOf(context);
      if (router == null) return '/';
      return router.routerDelegate.currentConfiguration.uri.path;
    }
  }

  static bool _locationIs(BuildContext context, String path) =>
      currentPath(context).startsWith(path);

  static void _goHome(BuildContext context, AppTab tab) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final target = '/?tab=${AppTab.values.indexOf(tab)}';
    if (router.routerDelegate.currentConfiguration.uri.toString() == target) {
      return;
    }
    router.go(target);
  }

  static void _goDestination(BuildContext context, String path) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.routerDelegate.currentConfiguration.uri.path == path) return;
    router.go(path);
  }

  static void _goTab(BuildContext context, WidgetRef ref, AppTab tab) {
    ref.read(workspaceTabProvider.notifier).state = tab;
    _goHome(context, tab);
  }

  static void _goTodosView(
    BuildContext context,
    WidgetRef ref,
    TodosView view,
  ) {
    ref.read(workspaceTabProvider.notifier).state = AppTab.todos;
    ref.read(todosViewProvider.notifier).state = view;
    _goHome(context, AppTab.todos);
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (compact) {
      return Center(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.sidebarSelected,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            CupertinoIcons.sparkles,
            size: 16,
            color: AppColors.sidebarInk,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, 0),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.sidebarSelected,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              CupertinoIcons.sparkles,
              size: 15,
              color: AppColors.sidebarInk,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: AppColors.sidebarInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SearchEntry extends StatelessWidget {
  const SearchEntry({super.key, required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Center(
        child: IconButton(
          icon: const Icon(CupertinoIcons.search, size: 18, color: AppColors.sidebarMuted),
          onPressed: onTap,
          tooltip: AppLocalizations.of(context)!.search,
        ),
      );
    }
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.sidebarSelected.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  size: 14,
                  color: AppColors.sidebarMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.search,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.sidebarMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? AppColors.sidebarSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: IconButton(
            icon: Icon(
              icon,
              size: 18,
              color: selected ? AppColors.sidebarInk : AppColors.sidebarMuted,
            ),
            onPressed: onTap,
            tooltip: label,
          ),
        ),
      );
    }
    return _SidebarRow(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: selected ? AppColors.sidebarInk : AppColors.sidebarMuted,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: selected ? AppColors.sidebarInk : AppColors.sidebarMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubNavigationItem extends StatelessWidget {
  const _SubNavigationItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SidebarRow(
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 29),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: selected ? AppColors.sidebarInk : AppColors.sidebarMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: selected ? AppColors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 7,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
