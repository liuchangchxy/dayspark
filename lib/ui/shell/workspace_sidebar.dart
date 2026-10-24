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

/// "Today" is a place, not a mode: selecting any other day inside Todo leaves
/// the day view active, so the label only lights up when the day really is
/// today.
bool _viewIsToday(TodosView view) {
  if (view is! TodosDayView) return false;
  final now = DateTime.now();
  final day = view.day;
  return day.year == now.year && day.month == now.month && day.day == now.day;
}

/// Desktop workspace rail. Lives outside the router so every destination —
/// Home, Settings, Search, a pushed detail — keeps the same chrome; the
/// selected destination is derived from the current location, not from the
/// page that happens to be on screen.
class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({super.key});

  static const double width = 232;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tab = ref.watch(workspaceTabProvider);
    final view = ref.watch(todosViewProvider);
    final showAi =
        ref
            .watch(featureFlagsProvider)
            .valueOrNull
            ?.isEnabled(FeatureFlag.aiAssistant) ??
        true;

    return Material(
      color: AppColors.sidebar,
      child: SizedBox(
        width: width,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _WorkspaceHeader(),
                const SizedBox(height: AppSpacing.md),
                SearchEntry(onTap: () => context.push('/search')),
                const SizedBox(height: AppSpacing.lg),
                _NavigationItem(
                  label: l.action,
                  icon: CupertinoIcons.bolt,
                  selected: tab == AppTab.action,
                  onTap: () => _goTab(context, ref, AppTab.action),
                ),
                _NavigationItem(
                  label: l.calendar,
                  icon: CupertinoIcons.calendar,
                  selected: tab == AppTab.calendar,
                  onTap: () => _goTab(context, ref, AppTab.calendar),
                ),
                _NavigationItem(
                  label: l.todos,
                  icon: CupertinoIcons.checkmark_rectangle,
                  selected: tab == AppTab.todos,
                  onTap: () => _goTab(context, ref, AppTab.todos),
                ),
                // Today and Inbox are places inside Todo, so they read as
                // children of it rather than as three more destinations.
                _SubNavigationItem(
                  label: l.today,
                  selected: tab == AppTab.todos && _viewIsToday(view),
                  onTap: () {
                    final now = DateTime.now();
                    _goTodosView(
                      context,
                      ref,
                      TodosDayView(DateTime(now.year, now.month, now.day)),
                    );
                  },
                ),
                _SubNavigationItem(
                  label: l.inbox,
                  selected: tab == AppTab.todos && view is TodosInboxView,
                  onTap: () =>
                      _goTodosView(context, ref, const TodosInboxView()),
                ),
                const SizedBox(height: AppSpacing.lg),
                _NavigationItem(
                  label: l.manageTags,
                  icon: CupertinoIcons.tag,
                  selected: _locationIs(context, '/tags'),
                  onTap: () => context.push('/tags'),
                ),
                _NavigationItem(
                  label: l.trash,
                  icon: CupertinoIcons.trash,
                  selected: _locationIs(context, '/trash'),
                  onTap: () => context.push('/trash'),
                ),
                if (showAi)
                  _NavigationItem(
                    label: l.aiAssistant,
                    icon: CupertinoIcons.sparkles,
                    selected: _locationIs(context, '/ai-chat'),
                    onTap: () => context.push('/ai-chat'),
                  ),
                const Spacer(),
                _NavigationItem(
                  label: l.settings,
                  icon: CupertinoIcons.settings,
                  selected: _locationIs(context, '/settings'),
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The rail renders inside several route shapes (the shell, a bare page in
  /// a test, the mobile fallback), so it cannot assume a [GoRouterState] is
  /// above it. When there is no router at all, nothing is "current".
  static String currentPath(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return '/';
    return router.routerDelegate.currentConfiguration.uri.path;
  }

  static bool _locationIs(BuildContext context, String path) =>
      currentPath(context).startsWith(path);

  /// Without a router (a bare page in a test or an embedding host) the
  /// provider write above is the whole interaction.
  static void _goHome(BuildContext context, AppTab tab) {
    GoRouter.maybeOf(context)?.go('/?tab=${AppTab.values.indexOf(tab)}');
  }

  static void _goTab(BuildContext context, WidgetRef ref, AppTab tab) {
    ref.read(workspaceTabProvider.notifier).state = tab;
    // Home is a route, not a widget the rail can mutate in place: the tab has
    // to travel with the navigation or a fresh Home would reset to the stored
    // default and the click would appear to do nothing.
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
  const _WorkspaceHeader();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              CupertinoIcons.calendar_badge_plus,
              size: 16,
              color: Colors.white,
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

/// Search is a workspace-wide destination, so it belongs to the chrome rather
/// than to whichever page is open.
class SearchEntry extends StatelessWidget {
  const SearchEntry({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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

/// Today / Inbox under Todo. Indented and uniconed so the nesting is legible
/// from the layout alone, without a disclosure caret to open.
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
