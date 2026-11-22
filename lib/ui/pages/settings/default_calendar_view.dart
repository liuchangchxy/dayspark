import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'settings_ui.dart';

class DefaultCalendarView extends ConsumerStatefulWidget {
  const DefaultCalendarView({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  ConsumerState<DefaultCalendarView> createState() =>
      _DefaultCalendarViewState();
}

class _DefaultCalendarViewState extends ConsumerState<DefaultCalendarView> {
  int? _selectedCalId;

  @override
  void initState() {
    super.initState();
    _selectedCalId = ref.read(defaultCalendarIdProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final currentDefault = ref.watch(defaultCalendarIdProvider);
    final activeId = _selectedCalId ?? currentDefault ?? (calendars.isNotEmpty ? calendars.first.id : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onBack,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.chevron_left, size: 14, color: SpecTokens.muted),
                      const SizedBox(width: 4),
                      Text(
                        l.general,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpecTokens.muted,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Text(
          l.defaultCalendar,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SpecTokens.ink,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.defaultCalendarDesc,
          style: const TextStyle(
            fontSize: 11,
            color: SpecTokens.faint,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: SpecTokens.paper,
            borderRadius: BorderRadius.circular(SpecTokens.r8),
            border: Border.all(color: SpecTokens.hair),
          ),
          child: Column(
            children: [
              for (var i = 0; i < calendars.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: SpecTokens.hair,
                  ),
                _CalendarOptionRow(
                  calendar: calendars[i],
                  isSelected: activeId == calendars[i].id,
                  onTap: () {
                    setState(() => _selectedCalId = calendars[i].id);
                  },
                ),
              ],
            ],
          ),
        ),
        InlineAlert(
          message: l.defaultCalendarAlert,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                if (activeId != null) {
                  await ref
                      .read(defaultCalendarIdProvider.notifier)
                      .setDefaultCalendarId(activeId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.defaultCalendarSaved)),
                    );
                    widget.onBack?.call();
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: SpecTokens.ink,
                  borderRadius: BorderRadius.circular(SpecTokens.r6),
                ),
                child: Text(
                  l.saveDefaultCalendar,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SpecTokens.paper,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarOptionRow extends StatelessWidget {
  const _CalendarOptionRow({
    required this.calendar,
    required this.isSelected,
    required this.onTap,
  });

  final Calendar calendar;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];
        final count = todos.where((t) => t.calendarId == calendar.id).length;
        final color = ColorUtils.parseHex(calendar.color);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? SpecTokens.ink : SpecTokens.paper,
                      border: Border.all(
                        color: isSelected
                            ? SpecTokens.ink
                            : const Color(0xFFCFCFC7),
                        width: 1.4,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            CupertinoIcons.checkmark,
                            size: 9.5,
                            color: SpecTokens.paper,
                          )
                        : null,
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
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: SpecTokens.ink,
                        fontFamilyFallback: AppTypography.fallback,
                      ),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.dayItemCount(count),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: SpecTokens.faint,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
