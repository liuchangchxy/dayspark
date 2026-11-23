import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/domain/providers/calendar_view_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/shell/workspace_scaffold.dart';

/// The 按日期 month / year sheet. Selecting a day writes the shared browse date
/// and closes the sheet, so every surface that reads the date follows at once.
///
/// The design draws it as a phone sheet; a window has no bottom edge to slide
/// from, so there it is the same grid in a centred card.
Future<void> showMonthYearPicker(
  BuildContext context, {
  required DateTime initial,
}) async {
  final ds = context.ds;
  if (isWorkspaceLayout(context)) {
    await showDialog<void>(
      context: context,
      barrierColor: ds.scrim,
      builder: (_) => _MonthYearPickerSheet(initial: initial, sheet: false),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: ds.scrim,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (_) => _MonthYearPickerSheet(initial: initial),
  );
}

class _MonthYearPickerSheet extends ConsumerStatefulWidget {
  const _MonthYearPickerSheet({required this.initial, this.sheet = true});

  final DateTime initial;
  final bool sheet;

  @override
  ConsumerState<_MonthYearPickerSheet> createState() =>
      _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends ConsumerState<_MonthYearPickerSheet> {
  late DateTime _selected;
  late DateTime _visibleMonth;
  bool _yearMode = false;

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(widget.initial);
    _visibleMonth = DateTime(widget.initial.year, widget.initial.month, 1);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String get _locale => Localizations.localeOf(context).toString();

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _pick(DateTime day) {
    final picked = _dateOnly(day);
    // One browsed date for the whole app: Todo · By date and the Calendar
    // both read it. The view only says which list is open.
    ref.read(viewedDateProvider.notifier).state = picked;
    Navigator.of(context).pop();
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + delta,
        1,
      );
    });
  }

  void _shiftYears(int delta) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year + delta * 12,
        _visibleMonth.month,
        1,
      );
    });
  }

  void _pickYear(int year) {
    setState(() {
      _visibleMonth = DateTime(year, _visibleMonth.month, 1);
      _yearMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final title = _yearMode
        ? '${_visibleMonth.year}'
        : DateFormat.yMMMM(_locale).format(_visibleMonth);

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsSheetChrome(
          title: title,
          showGrabber: widget.sheet,
          headerAction: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segmented(l),
              const SizedBox(width: AppSpacing.s2),
              _nav(),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _yearMode ? _yearGrid() : _monthGrid(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: _linkButton(
              l.goToToday,
              () => _pick(ref.read(calendarNowProvider)()),
            ),
          ),
        ),
      ],
    );

    if (widget.sheet) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: ds.line)),
          boxShadow: AppShadows.sheet(ds.brightness),
        ),
        child: SafeArea(top: false, child: column),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.s6),
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 620),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: AppRadii.dialog,
          border: Border.all(color: ds.line),
          boxShadow: AppShadows.two(ds.brightness),
        ),
        child: column,
      ),
    );
  }

  Widget _segmented(AppLocalizations l) {
    final ds = context.ds;
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ds.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            l.month,
            !_yearMode,
            () => setState(() => _yearMode = false),
          ),
          _segment(
            l.yearLabel,
            _yearMode,
            () => setState(() => _yearMode = true),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool on, VoidCallback onTap) {
    final ds = context.ds;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? ds.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: on
              ? const [
                  BoxShadow(
                    color: Color(0x0D141410),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
            color: on ? ds.ink : ds.ink2,
            fontFamilyFallback: AppTypography.fallback,
          ),
        ),
      ),
    );
  }

  Widget _nav() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _navButton(
          CupertinoIcons.chevron_left,
          _yearMode ? () => _shiftYears(-1) : () => _shiftMonth(-1),
        ),
        _navButton(
          CupertinoIcons.chevron_right,
          _yearMode ? () => _shiftYears(1) : () => _shiftMonth(1),
        ),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    final ds = context.ds;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 30,
        child: Center(child: Icon(icon, size: 14, color: ds.ink3)),
      ),
    );
  }

  Widget _monthGrid() {
    final ds = context.ds;
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final locale = _locale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              for (var index = 0; index < 7; index++) ...[
                if (index > 0) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    DateFormat.E(locale).format(DateTime(2024, 1, 1 + index)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: ds.ink3,
                      fontFamilyFallback: AppTypography.fallback,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        for (var row = 0; row < 6; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 4),
            child: Row(
              children: [
                for (var column = 0; column < 7; column++) ...[
                  if (column > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _dayCell(
                      start.add(Duration(days: row * 7 + column)),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _dayCell(DateTime day) {
    final ds = context.ds;
    final otherMonth = day.month != _visibleMonth.month;
    final today = _sameDay(day, ref.read(calendarNowProvider)());
    final selected = _sameDay(day, _selected);
    final background = today
        ? ds.primaryTint
        : selected
        ? ds.surface3
        : null;
    final color = today
        ? ds.primary
        : otherMonth
        ? ds.ink3.withValues(alpha: 0.45)
        : ds.ink;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('month-day-${day.year}-${day.month}-${day.day}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(day),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: otherMonth ? 12 : 13,
              fontWeight: today || selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
              height: 1,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ),
    );
  }

  Widget _yearGrid() {
    final startYear = _visibleMonth.year - 6;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (var row = 0; row < 4; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 8),
              child: Row(
                children: [
                  for (var column = 0; column < 3; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(child: _yearCell(startYear + row * 3 + column)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _yearCell(int year) {
    final ds = context.ds;
    final selected = year == _selected.year;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickYear(year),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ds.primary : ds.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$year',
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? ds.onPrimary : ds.ink,
              fontFeatures: AppTypography.tabular,
              fontFamilyFallback: AppTypography.fallback,
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkButton(String label, VoidCallback onTap) {
    final ds = context.ds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ds.primary,
                fontFamilyFallback: AppTypography.fallback,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
