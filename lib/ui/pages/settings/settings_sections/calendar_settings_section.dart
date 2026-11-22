import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';
import 'package:dayspark/domain/providers/default_calendar_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import '../settings_ui.dart';

const List<String> kFrozenCalendarColors = [
  '#4F7BBF',
  '#6A9464',
  '#C4794A',
  '#6C6FA8',
  '#A98B4F',
  '#8A8A82',
];

class CalendarSettingsSection extends ConsumerStatefulWidget {
  const CalendarSettingsSection({
    super.key,
    this.standalone = false,
    this.onOpenDefaultCalendar,
  });

  final bool standalone;
  final VoidCallback? onOpenDefaultCalendar;

  @override
  ConsumerState<CalendarSettingsSection> createState() =>
      _CalendarSettingsSectionState();
}

class _CalendarSettingsSectionState
    extends ConsumerState<CalendarSettingsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final defaultId = ref.watch(defaultCalendarIdProvider) ??
        (calendars.isNotEmpty ? calendars.first.id : null);
    final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];

    final listContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final cal in calendars) ...[
          _CalendarRow(
            calendar: cal,
            isDefault: cal.id == defaultId,
            itemCount: todos.where((t) => t.calendarId == cal.id).length,
            onTap: () => _showEditCalendarDialog(context, cal),
          ),
        ],
        // + 新建日历
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showNewCalendarDialog(context),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(CupertinoIcons.add, size: 12, color: SpecTokens.ink),
                  const SizedBox(width: 8),
                  Text(
                    l.newCalendar,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: SpecTokens.ink,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Text(
            l.deleteCalendarNotice,
            style: const TextStyle(
              fontSize: 10.5,
              color: SpecTokens.faint,
              height: 1.45,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ],
    );

    if (widget.standalone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.manageCalendars,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpecTokens.ink,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.calendarManagementDesc,
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
            child: listContent,
          ),
        ],
      );
    }

    return SettingsRows(
      children: [
        SettingsRow(
          label: l.manageCalendars,
          subtitle: l.calendarManagementDesc,
          value: l.categoryCount(calendars.length),
          chevron: _expanded ? SettingsChevron.down : SettingsChevron.right,
          onTap: () {
            setState(() => _expanded = !_expanded);
          },
        ),
        if (_expanded) listContent,
      ],
    );
  }

  void _showNewCalendarDialog(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    var selectedColor = kFrozenCalendarColors.first;
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: SpecTokens.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpecTokens.r12),
            side: const BorderSide(color: SpecTokens.hair),
          ),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.newCalendar,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SpecTokens.ink,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.newCalendarDesc,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpecTokens.faint,
                    height: 1.45,
                    fontFamilyFallback: AppTypography.fallback,
                  ),
                ),
                const SizedBox(height: 16),
                IoCard(
                  title: l.calendarName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CupertinoTextField(
                        controller: nameController,
                        autofocus: true,
                        placeholder: l.calendarPlaceholder,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SpecTokens.ink,
                          fontFamilyFallback: AppTypography.fallback,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: SpecTokens.wash,
                          borderRadius: BorderRadius.circular(SpecTokens.r6),
                          border: Border.all(
                            color: errorText != null
                                ? SpecTokens.red
                                : SpecTokens.hair2,
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          errorText!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: SpecTokens.red,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        l.calendarColorLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: SpecTokens.ink2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final c in kFrozenCalendarColors) ...[
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () =>
                                    setDialogState(() => selectedColor = c),
                                child: Container(
                                  width: 24,
                                  height: 20,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: ColorUtils.parseHex(c),
                                    borderRadius: BorderRadius.circular(4),
                                    border: c == selectedColor
                                        ? Border.all(
                                            color: SpecTokens.ink,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: SpecTokens.wash,
                            borderRadius: BorderRadius.circular(SpecTokens.r6),
                          ),
                          child: Text(
                            l.cancel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SpecTokens.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            setDialogState(
                              () => errorText = l.calendarNameRequired,
                            );
                            return;
                          }
                          await ref.read(createCalendarProvider)(
                            name: name,
                            color: selectedColor,
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: SpecTokens.ink,
                            borderRadius: BorderRadius.circular(SpecTokens.r6),
                          ),
                          child: Text(
                            l.create,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: SpecTokens.paper,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditCalendarDialog(BuildContext context, Calendar calendar) {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: calendar.name);
    var selectedColor = calendar.color;
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    final defaultId = ref.read(defaultCalendarIdProvider) ??
        (calendars.isNotEmpty ? calendars.first.id : null);
    final isDefault = calendar.id == defaultId;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: SpecTokens.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpecTokens.r12),
            side: const BorderSide(color: SpecTokens.hair),
          ),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.editCalendar,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SpecTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.editCalendarDesc(calendar.name),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpecTokens.faint,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                IoCard(
                  title: l.calendarName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CupertinoTextField(
                        controller: nameController,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SpecTokens.ink,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: SpecTokens.wash,
                          borderRadius: BorderRadius.circular(SpecTokens.r6),
                          border: Border.all(color: SpecTokens.hair2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.calendarColorLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: SpecTokens.ink2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final c in kFrozenCalendarColors) ...[
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () =>
                                    setDialogState(() => selectedColor = c),
                                child: Container(
                                  width: 24,
                                  height: 20,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: ColorUtils.parseHex(c),
                                    borderRadius: BorderRadius.circular(4),
                                    border: c.toLowerCase() ==
                                            selectedColor.toLowerCase()
                                        ? Border.all(
                                            color: SpecTokens.ink,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isDefault
                                ? l.currentCalendarIsDefault
                                : '${l.currentDefaultPrefix}${calendars.firstWhere((c) => c.id == defaultId, orElse: () => calendars.first).name}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: SpecTokens.muted,
                            ),
                          ),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                widget.onOpenDefaultCalendar?.call();
                              },
                              child: Text(
                                l.goToSettings,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).primaryColor,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (calendars.length > 1)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _showDeleteMigrationDialog(context, calendar);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: SpecTokens.redSoft,
                              borderRadius:
                                  BorderRadius.circular(SpecTokens.r6),
                            ),
                            child: Text(
                              l.deleteCalendar,
                              style: const TextStyle(
                                fontSize: 12,
                                color: SpecTokens.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(),
                    Row(
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: SpecTokens.wash,
                                borderRadius:
                                    BorderRadius.circular(SpecTokens.r6),
                              ),
                              child: Text(
                                l.cancel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SpecTokens.ink2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) return;
                              await ref.read(updateCalendarProvider)(
                                id: calendar.id,
                                name: name,
                                color: selectedColor,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: SpecTokens.ink,
                                borderRadius:
                                    BorderRadius.circular(SpecTokens.r6),
                              ),
                              child: Text(
                                l.save,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: SpecTokens.paper,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteMigrationDialog(
    BuildContext context,
    Calendar calendar,
  ) async {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.read(calendarsProvider).valueOrNull ?? const [];
    final targets = calendars.where((c) => c.id != calendar.id).toList();
    final db = ref.read(databaseProvider);
    final eventCount = await (db.select(
      db.events,
    )..where((row) => row.calendarId.equals(calendar.id))).get();
    final todoCount = await (db.select(
      db.todos,
    )..where((row) => row.calendarId.equals(calendar.id))).get();
    if (!context.mounted) return;
    final totalCount = eventCount.length + todoCount.length;

    var selectedTargetId = targets.isNotEmpty ? targets.first.id : null;
    var deleteAllTogether = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: SpecTokens.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpecTokens.r12),
            side: const BorderSide(color: SpecTokens.hair),
          ),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.deleteCalendar,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SpecTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.deleteCalendarHeader(calendar.name, totalCount),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpecTokens.faint,
                    height: 1.45,
                  ),
                ),
                InlineAlert(
                  message: l.deleteCalendarWarning,
                  isRed: true,
                ),
                const SizedBox(height: 14),
                if (targets.isNotEmpty) ...[
                  IoCard(
                    title: l.migrateTo,
                    child: Column(
                      children: [
                        for (final target in targets)
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setDialogState(() {
                                selectedTargetId = target.id;
                                deleteAllTogether = false;
                              }),
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 38),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: selectedTargetId == target.id &&
                                                !deleteAllTogether
                                            ? SpecTokens.ink
                                            : SpecTokens.paper,
                                        border: Border.all(
                                          color: selectedTargetId == target.id &&
                                                  !deleteAllTogether
                                              ? SpecTokens.ink
                                              : const Color(0xFFCFCFC7),
                                          width: 1.4,
                                        ),
                                      ),
                                      child: selectedTargetId == target.id &&
                                              !deleteAllTogether
                                          ? const Icon(
                                              CupertinoIcons.checkmark,
                                              size: 9.5,
                                              color: SpecTokens.paper,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l.migrateItemCount(target.name, totalCount),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: SpecTokens.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                IoCard(
                  title: l.orAlternative,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setDialogState(() {
                        deleteAllTogether = true;
                      }),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 38),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: deleteAllTogether
                                    ? SpecTokens.ink
                                    : SpecTokens.paper,
                                border: Border.all(
                                  color: deleteAllTogether
                                      ? SpecTokens.ink
                                      : const Color(0xFFCFCFC7),
                                  width: 1.4,
                                ),
                              ),
                              child: deleteAllTogether
                                  ? const Icon(
                                      CupertinoIcons.checkmark,
                                      size: 9.5,
                                      color: SpecTokens.paper,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l.deleteWithContents(totalCount),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SpecTokens.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: SpecTokens.wash,
                            borderRadius: BorderRadius.circular(SpecTokens.r6),
                          ),
                          child: Text(
                            l.cancel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SpecTokens.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          await ref.read(deleteCalendarProvider)(
                            calendar.id,
                            moveContentsTo: deleteAllTogether ? null : selectedTargetId,
                            deleteContents: deleteAllTogether,
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: SpecTokens.red,
                            borderRadius: BorderRadius.circular(SpecTokens.r6),
                          ),
                          child: Text(
                            l.confirmMigrateAndDelete,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: SpecTokens.paper,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.calendar,
    required this.isDefault,
    required this.itemCount,
    required this.onTap,
  });

  final Calendar calendar;
  final bool isDefault;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = ColorUtils.parseHex(calendar.color);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: SpecTokens.hair, width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                calendar.name,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              if (isDefault) ...[
                const SizedBox(width: 8),
                const BadgeDefault(),
              ],
              const Spacer(),
              Text(
                AppLocalizations.of(context)!.dayItemCount(itemCount),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: SpecTokens.faint,
                  fontFamilyFallback: AppTypography.fallback,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 11,
                color: SpecTokens.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
