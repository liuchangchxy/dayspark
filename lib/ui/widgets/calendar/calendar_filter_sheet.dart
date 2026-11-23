import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

final calendarFilterCountsProvider =
    StreamProvider.autoDispose<Map<int, int>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.calendarsDao.watchAll().asyncMap((calendars) async {
        final events = await (db.select(db.events)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final todos = await (db.select(db.todos)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final counts = <int, int>{};
        for (final e in events) {
          counts[e.calendarId] = (counts[e.calendarId] ?? 0) + 1;
        }
        for (final t in todos) {
          counts[t.calendarId] = (counts[t.calendarId] ?? 0) + 1;
        }
        return counts;
      });
    });

class CalendarFilterSheet extends ConsumerWidget {
  const CalendarFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    return showDialog<void>(
      context: context,
      barrierColor: isDesktop ? Colors.transparent : Colors.black26,
      builder: (_) => Stack(
        children: [
          if (isDesktop)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          Positioned(
            top: isDesktop ? 118 : null,
            right: isDesktop ? 28 : null,
            left: isDesktop ? null : 20,
            bottom: isDesktop ? null : 20,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: isDesktop ? 260 : MediaQuery.sizeOf(context).width - 40,
                child: const CalendarFilterSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? <Calendar>[];
    final hiddenIds = ref.watch(calendarHiddenFilterProvider);
    final counts = ref.watch(calendarFilterCountsProvider).valueOrNull ?? const <int, int>{};

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: l.showCalendars,
      child: Container(
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ds.line),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(25, 25, 24, 0.12),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ds.lineSoft)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.showCalendars,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ds.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(CupertinoIcons.xmark, size: 14, color: ds.ink3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final cal in calendars) ...[
                      _CalendarRow(
                        calendar: cal,
                        hidden: hiddenIds.contains(cal.id),
                        count: counts[cal.id] ?? 0,
                        onToggle: () {
                          final next = Set<int>.from(hiddenIds);
                          if (next.contains(cal.id)) {
                            next.remove(cal.id);
                          } else {
                            next.add(cal.id);
                          }
                          ref.read(calendarHiddenFilterProvider.notifier).state = next;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: ds.lineSoft)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: TextButton(
                      onPressed: () {
                        ref.read(calendarHiddenFilterProvider.notifier).state = const <int>{};
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: ds.ink2,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(40, 30),
                      ),
                      child: Text(
                        l.selectAll,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: ds.primary,
                        foregroundColor: ds.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: const Size(48, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text(
                        l.done,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.calendar,
    required this.hidden,
    required this.count,
    required this.onToggle,
  });

  final Calendar calendar;
  final bool hidden;
  final int count;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final color = ColorUtils.parseHex(calendar.color);

    return Semantics(
      checked: !hidden,
      label: '${calendar.name}${hidden ? " ${l.hiddenBadge}" : ""}',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onToggle,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: hidden ? Colors.transparent : ds.primary,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: hidden ? ds.line : ds.primary,
                    width: 1.5,
                  ),
                ),
                child: hidden
                    ? null
                    : Icon(CupertinoIcons.checkmark, size: 12, color: ds.onPrimary),
              ),
              const SizedBox(width: 10),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  calendar.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: hidden ? ds.ink3 : ds.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: ds.ink3,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              if (hidden) ...[
                const SizedBox(width: 6),
                Text(
                  l.hiddenBadge,
                  style: TextStyle(
                    fontSize: 11,
                    color: ds.ink3,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  }
}
