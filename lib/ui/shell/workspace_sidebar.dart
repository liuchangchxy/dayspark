import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/action_projection_provider.dart';
import 'package:dayspark/domain/providers/default_tab_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_navigation.dart';

/// Desktop rail: navigation, calendars and tags on paper — not a dark
/// application frame. 236px wide, folding to a 64px icon rail under 980.
class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({super.key});

  static const double width = 236;
  static const double compactWidth = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final compact = MediaQuery.sizeOf(context).width < 980;
    final path = currentPath(context);
    final isHome = path == '/';
    final tab = isHome ? ref.watch(workspaceTabProvider) : null;
    final view = ref.watch(todosViewProvider);
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? const [];
    final projection = ref.watch(actionProjectionProvider).valueOrNull;
    final allTodos = ref.watch(allTodosProvider).valueOrNull ?? const [];
    final trashed = ref.watch(deletedTodosProvider).valueOrNull ?? const [];
    final unplanned = ref.watch(unplannedTodosProvider).valueOrNull ?? const [];
    final calendarFilter = ref.watch(todoCalendarFilterProvider);
    final todayCount = projection == null
        ? 0
        : projection.dueTodayTodos.length + projection.overdueTodos.length;
    final activeCount = allTodos
        .where((t) => t.status != 'COMPLETED' && t.status != 'CANCELLED')
        .length;

    return Container(
      width: compact ? compactWidth : width,
      decoration: BoxDecoration(
        color: ds.navBg,
        border: Border(right: BorderSide(color: ds.line)),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.s1 + 2 : 10,
            AppSpacing.s3,
            compact ? AppSpacing.s1 + 2 : 10,
            AppSpacing.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Brand(compact: compact),
              const SizedBox(height: AppSpacing.s3),
              _SearchButton(
                compact: compact,
                onTap: () => _go(context, '/search'),
              ),
              const SizedBox(height: AppSpacing.s3),
              _NavItem(
                key: const ValueKey('nav-today'),
                compact: compact,
                label: l.today,
                icon: CupertinoIcons.time,
                count: todayCount == 0 ? null : todayCount,
                selected: tab == AppTab.action && isHome,
                onTap: () => _goTab(context, ref, AppTab.action),
              ),
              _NavItem(
                key: const ValueKey('nav-calendar'),
                compact: compact,
                label: l.calendar,
                icon: CupertinoIcons.calendar,
                selected: tab == AppTab.calendar && isHome,
                onTap: () => _goTab(context, ref, AppTab.calendar),
              ),
              _NavItem(
                key: const ValueKey('nav-todos'),
                compact: compact,
                label: l.todos,
                icon: CupertinoIcons.checkmark_square,
                count: activeCount,
                selected: tab == AppTab.todos && isHome,
                onTap: () => _goTodosView(context, ref, const TodosAllView()),
              ),
              if (!compact) ...[
                _SubNavItem(
                  label: l.inbox,
                  count: unplanned.length,
                  selected: tab == AppTab.todos &&
                      isHome &&
                      view is TodosInboxView,
                  onTap: () =>
                      _goTodosView(context, ref, const TodosInboxView()),
                ),
                _SubNavItem(
                  label: l.allTasks,
                  selected: tab == AppTab.todos &&
                      isHome &&
                      view is TodosAllView &&
                      calendarFilter == null,
                  onTap: () {
                    ref.read(todoCalendarFilterProvider.notifier).state = null;
                    _goTodosView(context, ref, const TodosAllView());
                  },
                ),
              ],
              if (compact)
                const Spacer()
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: AppSpacing.s1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NavLabel(l.calendar),
                        for (final calendar in calendars)
                          _CategoryRow(
                            label: calendar.name,
                            color: ColorUtils.parseHex(calendar.color),
                            count: allTodos
                                .where(
                                  (t) =>
                                      t.calendarId == calendar.id &&
                                      t.status != 'COMPLETED' &&
                                      t.status != 'CANCELLED',
                                )
                                .length,
                            selected: calendarFilter == calendar.id,
                            onTap: () {
                              ref
                                  .read(todoCalendarFilterProvider.notifier)
                                  .state = calendar.id;
                              _goTodosView(
                                context,
                                ref,
                                const TodosAllView(),
                              );
                            },
                          ),
                        if (tags.isNotEmpty) _NavLabel(l.tags),
                        for (final tag in tags)
                          _CategoryRow(
                            label: tag.name,
                            color: ColorUtils.parseHex(tag.color),
                            onTap: () {
                              ref.read(todoTagFilterProvider.notifier).state = {
                                tag.id,
                              };
                              _goTodosView(
                                context,
                                ref,
                                const TodosAllView(),
                              );
                            },
                          ),
                        _NavLabel(l.moreSection),
                        _CategoryRow(
                          label: l.manageCalendars,
                          icon: CupertinoIcons.calendar_badge_plus,
                          selected: path.startsWith('/calendars'),
                          onTap: () => _go(context, '/calendars'),
                        ),
                        _CategoryRow(
                          label: l.trash,
                          icon: CupertinoIcons.trash,
                          count: trashed.length,
                          selected: path.startsWith('/trash'),
                          onTap: () => _go(context, '/trash'),
                        ),
                      ],
                    ),
                  ),
                ),
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.s1),
                padding: const EdgeInsets.only(top: AppSpacing.s1),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: ds.lineSoft)),
                ),
                child: _NavItem(
                  compact: compact,
                  label: l.settings,
                  icon: CupertinoIcons.gear,
                  selected: path.startsWith('/settings'),
                  onTap: () => _go(context, '/settings'),
                ),
              ),
            ],
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

  static void _go(BuildContext context, String path) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.routerDelegate.currentConfiguration.uri.path == path) return;
    router.go(path);
  }

  static void _goHome(BuildContext context, AppTab tab) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final target = '/?tab=${AppTab.values.indexOf(tab)}';
    if (router.routerDelegate.currentConfiguration.uri.toString() == target) {
      return;
    }
    router.go(target);
  }

  static void _goTab(BuildContext context, WidgetRef ref, AppTab tab) {
    ref.read(workspaceTabProvider.notifier).setTab(tab);
    _goHome(context, tab);
  }

  static void _goTodosView(
    BuildContext context,
    WidgetRef ref,
    TodosView view,
  ) {
    ref.read(workspaceTabProvider.notifier).setTab(AppTab.todos);
    ref.read(todosViewProvider.notifier).state = view;
    _goHome(context, AppTab.todos);
  }
}

class _Brand extends StatefulWidget {
  const _Brand({required this.compact});
  final bool compact;

  @override
  State<_Brand> createState() => _BrandState();
}

class _BrandState extends State<_Brand> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = info.version);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final compact = widget.compact;
    final mark = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ds.ink,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Text(
        'D',
        style: TextStyle(
          color: ds.surface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
    if (compact) {
      return Center(child: mark);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s2, AppSpacing.s1, AppSpacing.s2, 0),
      child: Row(
        children: [
          mark,
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ds.ink,
                    height: 1.2,
                  ),
                ),
                Text(
                  _version == null ? '' : 'v$_version',
                  style: AppTypography.overline.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 0,
                    color: ds.ink3,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final body = Container(
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 9),
      decoration: BoxDecoration(
        color: ds.surface2,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisAlignment:
            compact ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.search, size: 15, color: ds.ink3),
          if (!compact) ...[
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.search,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.small.copyWith(
                  fontSize: 12.5,
                  color: ds.ink3,
                ),
              ),
            ),
            const DsKeyCap('Ctrl K'),
          ],
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: body,
        ),
      ),
    );
  }
}

class _NavLabel extends StatelessWidget {
  const _NavLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(9, AppSpacing.s3 + 4, 9, 5),
    child: Text(
      label,
      style: AppTypography.overline.copyWith(
        fontSize: 11,
        letterSpacing: 0.55,
        color: context.ds.ink3,
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return _SidebarButton(
      selected: selected,
      selectedColor: ds.surface2,
      onTap: onTap,
      tooltip: compact ? label : null,
      child: SizedBox(
        height: 32,
        child: Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: selected ? ds.ink : ds.ink2),
            if (!compact) ...[
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? ds.ink : ds.ink2,
                  ),
                ),
              ),
              if (count != null && count! > 0)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: ds.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Material(
        color: selected ? ds.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          hoverColor: ds.surface2,
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                const SizedBox(width: 31),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? ds.ink : ds.ink2,
                    ),
                  ),
                ),
                if (count != null && count! > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: ds.ink3,
                        fontFeatures: const [FontFeature.tabularFigures()],
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    this.color,
    this.icon,
    this.count,
    this.selected = false,
    required this.onTap,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Material(
      color: selected ? ds.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        hoverColor: ds.surface2,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                if (color != null)
                  DsDot(color: color!, size: 6)
                else
                  Icon(icon, size: 15, color: ds.ink2),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: selected ? ds.ink : ds.ink2,
                    ),
                  ),
                ),
                if (count != null && count! > 0)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: ds.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.child,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.tooltip,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final Color? selectedColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: selected ? (selectedColor ?? ds.surface2) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            hoverColor: ds.surface2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: child,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return row;
    return Tooltip(message: tooltip!, child: row);
  }
}

/// Kept for the old call sites that only needed the search affordance.
class SearchEntry extends StatelessWidget {
  const SearchEntry({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SearchButton(
    compact: false,
    onTap: onTap,
  );
}
