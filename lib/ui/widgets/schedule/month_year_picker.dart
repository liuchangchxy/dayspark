import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/design/ds.dart';

/// A month/year first date picker: year arrows, twelve months, then the days
/// of the chosen month. It replaces the "tap next sixty times" path that the
/// strip alone allowed, and it always shows the year.
Future<DateTime?> showMonthYearPicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? today,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: context.ds.scrim,
    builder: (ctx) => _MonthYearPicker(
      initial: initial,
      today: today ?? DateTime.now(),
    ),
  );
}

class _MonthYearPicker extends StatefulWidget {
  const _MonthYearPicker({required this.initial, required this.today});

  final DateTime initial;
  final DateTime today;

  @override
  State<_MonthYearPicker> createState() => _MonthYearPickerState();
}

class _MonthYearPickerState extends State<_MonthYearPicker> {
  late int _year = widget.initial.year;
  late int? _month = widget.initial.month;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final month = _month;

    return Dialog(
      backgroundColor: ds.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s2,
                AppSpacing.s2,
              ),
              child: Row(
                children: [
                  if (month != null)
                    DsIconButton(
                      icon: CupertinoIcons.chevron_back,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () => setState(() => _month = null),
                    )
                  else
                    const SizedBox(width: 36),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _month = null),
                      child: Text(
                        month == null
                            ? _year.toString()
                            : DateFormat.yMMMM(
                                locale,
                              ).format(DateTime(_year, month)),
                        textAlign: TextAlign.center,
                        style: AppTypography.title.copyWith(color: ds.ink),
                      ),
                    ),
                  ),
                  DsIconButton(
                    icon: CupertinoIcons.xmark,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (month == null) ...[
              _YearRow(
                year: _year,
                onPrevious: () => setState(() => _year--),
                onNext: () => setState(() => _year++),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    0,
                    AppSpacing.s4,
                    AppSpacing.s3,
                  ),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.s1 + 2,
                    crossAxisSpacing: AppSpacing.s1 + 2,
                    childAspectRatio: 2.1,
                    children: [
                      for (var m = 1; m <= 12; m++)
                        _MonthCell(
                          label: DateFormat.MMM(locale).format(
                            DateTime(_year, m),
                          ),
                          selected:
                              _year == widget.initial.year &&
                              m == widget.initial.month,
                          onTap: () => setState(() => _month = m),
                        ),
                    ],
                  ),
                ),
              ),
            ] else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    0,
                    AppSpacing.s4,
                    AppSpacing.s3,
                  ),
                  child: _DayGrid(
                    year: _year,
                    month: month,
                    selected: widget.initial,
                    today: widget.today,
                    onSelected: (day) => Navigator.of(context).pop(day),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    DateTime(
                      widget.today.year,
                      widget.today.month,
                      widget.today.day,
                    ),
                  ),
                  child: Text(l.today),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearRow extends StatelessWidget {
  const _YearRow({
    required this.year,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DsIconButton(
          icon: CupertinoIcons.chevron_back,
          tooltip: '',
          onPressed: onPrevious,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
          child: Text(
            '$year',
            style: AppTypography.body.copyWith(
              color: context.ds.ink2,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ),
        DsIconButton(
          icon: CupertinoIcons.chevron_forward,
          tooltip: '',
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Material(
      color: selected ? ds.primarySoft : ds.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              color: selected ? ds.primary : ds.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.year,
    required this.month,
    required this.selected,
    required this.today,
    required this.onSelected,
  });

  final int year;
  final int month;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final first = DateTime(year, month);
    final firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final leading = (first.weekday - 1 - firstDay + 7) % 7;
    final days = DateTime(year, month + 1, 0).day;
    final today = DateTime(this.today.year, this.today.month, this.today.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat.E(locale).format(
                      DateTime(2024, 1, 7 + (firstDay + i) % 7),
                    ),
                    style: AppTypography.small.copyWith(color: ds.ink3),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              _DayCell(
                day: DateTime(year, month, d),
                isToday: DateTime(year, month, d) == today,
                isSelected: DateTime(year, month, d) ==
                    DateTime(selected.year, selected.month, selected.day),
                onTap: onSelected,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Material(
      color: isSelected ? ds.primary : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onTap(day),
        child: Center(
          child: Text(
            '${day.day}',
            style: AppTypography.small.copyWith(
              color: isSelected
                  ? ds.surface
                  : isToday
                  ? ds.primary
                  : ds.ink,
              fontWeight: isToday || isSelected
                  ? FontWeight.w600
                  : FontWeight.w400,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ),
      ),
    );
  }
}
