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
import 'package:dayspark/ui/design/ds.dart';
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

enum _CalSubpage { list, newCal, editCal, deleteCal }

class _CalendarSettingsSectionState
    extends ConsumerState<CalendarSettingsSection> {
  bool _expanded = false;
  _CalSubpage _subpage = _CalSubpage.list;
  Calendar? _targetCalendar;
  final TextEditingController _nameController = TextEditingController();
  String _selectedColor = kFrozenCalendarColors.first;
  String? _errorText;
  int? _selectedTargetId;
  bool _deleteAllTogether = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _openNewCalendar() {
    _nameController.text = '';
    _selectedColor = kFrozenCalendarColors.first;
    _errorText = null;
    setState(() => _subpage = _CalSubpage.newCal);
  }

  void _openEditCalendar(Calendar calendar) {
    _targetCalendar = calendar;
    _nameController.text = calendar.name;
    _selectedColor = calendar.color;
    _errorText = null;
    setState(() => _subpage = _CalSubpage.editCal);
  }

  void _openDeleteCalendar(Calendar calendar) {
    _targetCalendar = calendar;
    _selectedTargetId = null;
    _deleteAllTogether = false;
    setState(() => _subpage = _CalSubpage.deleteCal);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final calendars = ref.watch(calendarsProvider).valueOrNull ?? const [];
    final defaultId = ref.watch(defaultCalendarIdProvider) ??
        (calendars.isNotEmpty ? calendars.first.id : null);
    final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];
    final events = ref.watch(allEventsProvider).valueOrNull ?? const [];

    if (_subpage == _CalSubpage.newCal) {
      return _buildNewCalendarSubpage(context, l);
    }
    if (_subpage == _CalSubpage.editCal && _targetCalendar != null) {
      final currentCal = calendars.firstWhere(
        (c) => c.id == _targetCalendar!.id,
        orElse: () => _targetCalendar!,
      );
      return _buildEditCalendarSubpage(context, l, currentCal, calendars, defaultId);
    }
    if (_subpage == _CalSubpage.deleteCal && _targetCalendar != null) {
      return _buildDeleteCalendarSubpage(context, l, _targetCalendar!, calendars);
    }

    final calendarRows = <Widget>[
      for (final cal in calendars)
        _CalendarRow(
          calendar: cal,
          isDefault: cal.id == defaultId,
          itemCount: todos.where((t) => t.calendarId == cal.id).length +
              events.where((e) => e.calendarId == cal.id).length,
          onTap: () => _openEditCalendar(cal),
        ),
      _AddCalendarRow(
        label: l.newCalendar,
        onTap: _openNewCalendar,
      ),
    ];

    final notice = Padding(
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
          DsGroup(margin: EdgeInsets.zero, children: calendarRows),
          notice,
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
        if (_expanded) ...[
          ...calendarRows,
          notice,
        ],
      ],
    );
  }

  Widget _backButton(AppLocalizations l) {
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _subpage = _CalSubpage.list),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.chevron_left, size: 14, color: SpecTokens.muted),
                const SizedBox(width: 4),
                Text(
                  l.manageCalendars,
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
    );
  }

  Widget _buildNewCalendarSubpage(BuildContext context, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _backButton(l),
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
                controller: _nameController,
                autofocus: true,
                placeholder: l.calendarPlaceholder,
                style: const TextStyle(
                  fontSize: 13,
                  color: SpecTokens.ink,
                  fontFamilyFallback: AppTypography.fallback,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: SpecTokens.wash,
                  borderRadius: BorderRadius.circular(SpecTokens.r6),
                  border: Border.all(
                    color: _errorText != null ? SpecTokens.red : SpecTokens.hair2,
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style: const TextStyle(fontSize: 10.5, color: SpecTokens.red),
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
                  for (final c in kFrozenCalendarColors)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 24,
                          height: 20,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: ColorUtils.parseHex(c),
                            borderRadius: BorderRadius.circular(4),
                            border: c == _selectedColor
                                ? Border.all(color: SpecTokens.ink, width: 2)
                                : null,
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
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DsButton(
              label: l.cancel,
              tone: DsButtonTone.secondary,
              onPressed: () => setState(() => _subpage = _CalSubpage.list),
            ),
            const SizedBox(width: 8),
            DsButton(
              label: l.create,
              onPressed: () async {
                final name = _nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => _errorText = l.calendarNameRequired);
                  return;
                }
                await ref.read(createCalendarProvider)(
                  name: name,
                  color: _selectedColor,
                );
                if (mounted) setState(() => _subpage = _CalSubpage.list);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditCalendarSubpage(
    BuildContext context,
    AppLocalizations l,
    Calendar calendar,
    List<Calendar> calendars,
    int? defaultId,
  ) {
    final isDefault = calendar.id == defaultId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _backButton(l),
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
                controller: _nameController,
                style: const TextStyle(
                  fontSize: 13,
                  color: SpecTokens.ink,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  for (final c in kFrozenCalendarColors)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 24,
                          height: 20,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: ColorUtils.parseHex(c),
                            borderRadius: BorderRadius.circular(4),
                            border: c.toLowerCase() == _selectedColor.toLowerCase()
                                ? Border.all(color: SpecTokens.ink, width: 2)
                                : null,
                          ),
                        ),
                      ),
                    ),
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
                      onTap: widget.onOpenDefaultCalendar,
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
              DsButton(
                label: l.deleteCalendar,
                tone: DsButtonTone.danger,
                onPressed: () => _openDeleteCalendar(calendar),
              )
            else
              const SizedBox(),
            Row(
              children: [
                DsButton(
                  label: l.cancel,
                  tone: DsButtonTone.secondary,
                  onPressed: () => setState(() => _subpage = _CalSubpage.list),
                ),
                const SizedBox(width: 8),
                DsButton(
                  label: l.save,
                  onPressed: () async {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;
                    await ref.read(updateCalendarProvider)(
                      id: calendar.id,
                      name: name,
                      color: _selectedColor,
                    );
                    if (mounted) setState(() => _subpage = _CalSubpage.list);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeleteCalendarSubpage(
    BuildContext context,
    AppLocalizations l,
    Calendar calendar,
    List<Calendar> calendars,
  ) {
    final targets = calendars.where((c) => c.id != calendar.id).toList();
    final todos = ref.watch(allTodosProvider).valueOrNull ?? const [];
    final events = ref.watch(allEventsProvider).valueOrNull ?? const [];
    final totalCount = todos.where((t) => t.calendarId == calendar.id).length +
        events.where((e) => e.calendarId == calendar.id).length;

    _selectedTargetId ??= targets.isNotEmpty ? targets.first.id : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _subpage = _CalSubpage.editCal),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.chevron_left, size: 14, color: SpecTokens.muted),
                    const SizedBox(width: 4),
                    Text(
                      calendar.name,
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
                      onTap: () => setState(() {
                        _selectedTargetId = target.id;
                        _deleteAllTogether = false;
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
                                color: _selectedTargetId == target.id &&
                                        !_deleteAllTogether
                                    ? SpecTokens.ink
                                    : SpecTokens.paper,
                                border: Border.all(
                                  color: _selectedTargetId == target.id &&
                                          !_deleteAllTogether
                                      ? SpecTokens.ink
                                      : const Color(0xFFCFCFC7),
                                  width: 1.4,
                                ),
                              ),
                              child: _selectedTargetId == target.id &&
                                      !_deleteAllTogether
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
              onTap: () => setState(() {
                _deleteAllTogether = true;
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
                        color: _deleteAllTogether
                            ? SpecTokens.ink
                            : SpecTokens.paper,
                        border: Border.all(
                          color: _deleteAllTogether
                              ? SpecTokens.ink
                              : const Color(0xFFCFCFC7),
                          width: 1.4,
                        ),
                      ),
                      child: _deleteAllTogether
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
            DsButton(
              label: l.cancel,
              tone: DsButtonTone.secondary,
              onPressed: () => setState(() => _subpage = _CalSubpage.list),
            ),
            const SizedBox(width: 8),
            DsButton(
              label: l.confirmMigrateAndDelete,
              tone: DsButtonTone.danger,
              onPressed: () async {
                await ref.read(deleteCalendarProvider)(
                  calendar.id,
                  moveContentsTo: _deleteAllTogether ? null : _selectedTargetId,
                  deleteContents: _deleteAllTogether,
                );
                if (mounted) setState(() => _subpage = _CalSubpage.list);
              },
            ),
          ],
        ),
      ],
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
    return DsSettingRow(
      label: calendar.name,
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDefault) ...[
            const BadgeDefault(),
            const SizedBox(width: 8),
          ],
          Text(
            AppLocalizations.of(context)!.dayItemCount(itemCount),
            style: const TextStyle(
              fontSize: 10.5,
              color: SpecTokens.faint,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ],
      ),
      chevron: true,
      onTap: onTap,
    );
  }
}

class _AddCalendarRow extends StatelessWidget {
  const _AddCalendarRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DsSettingRow(
      label: label,
      leading: const Icon(
        CupertinoIcons.add,
        size: 12,
        color: SpecTokens.ink,
      ),
      // A zero trailing keeps the row from drawing a navigation chevron on a
      // create action.
      trailing: const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}
