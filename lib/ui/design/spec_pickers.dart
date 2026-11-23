import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:dayspark/core/theme/app_colors.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'ds.dart';

/// The frozen spec's two pickers: a 320px month card and an inline clock card.
///
/// Material's pickers are the one surface the spec never drew: they carry a
/// Material header, a blue dial and a blue selection that read as another
/// product. Both pickers here reuse the app's own dialog chrome so a date
/// prompt cannot drift away from every other overlay.
Future<DateTime?> showSpecDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: context.ds.scrim,
    builder: (_) => SpecDatePickerDialog(
      initialDate: DateUtils.dateOnly(initialDate),
      firstDate: firstDate == null ? null : DateUtils.dateOnly(firstDate),
      lastDate: lastDate == null ? null : DateUtils.dateOnly(lastDate),
    ),
  );
}

Future<TimeOfDay?> showSpecTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    barrierColor: context.ds.scrim,
    builder: (_) => SpecTimePickerDialog(initialTime: initialTime),
  );
}

class SpecDatePickerDialog extends StatefulWidget {
  const SpecDatePickerDialog({
    super.key,
    required this.initialDate,
    this.firstDate,
    this.lastDate,
  });

  final DateTime initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<SpecDatePickerDialog> createState() => _SpecDatePickerDialogState();
}

class _SpecDatePickerDialogState extends State<SpecDatePickerDialog> {
  late DateTime _selected;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _visibleMonth = DateTime(_selected.year, _selected.month);
  }

  bool _isEnabled(DateTime day) {
    final first = widget.firstDate;
    final last = widget.lastDate;
    if (first != null && day.isBefore(first)) return false;
    if (last != null && day.isAfter(last)) return false;
    return true;
  }

  void _goMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _select(DateTime day) {
    setState(() {
      _selected = day;
      _visibleMonth = DateTime(day.year, day.month);
    });
  }

  List<DateTime> get _cells {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final start = DateUtils.addDaysToDate(first, -(first.weekday - 1));
    return [for (var i = 0; i < 42; i++) DateUtils.addDaysToDate(start, i)];
  }

  String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return DsDialog(
      title: l.pickDateHint,
      width: 320,
      actions: [
        Expanded(
          child: DsButton(
            label: l.cancel,
            tone: DsButtonTone.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: DsButton(
            label: l.ok,
            expand: true,
            onPressed: () => Navigator.of(context).pop(_selected),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _monthHeader(context, ds, l),
          const SizedBox(height: AppSpacing.s2),
          _weekdayRow(context, ds),
          _monthGrid(context, ds),
        ],
      ),
    );
  }

  Widget _monthHeader(BuildContext context, DsColors ds, AppLocalizations l) {
    return Row(
      children: [
        DsIconButton(
          icon: CupertinoIcons.chevron_left,
          compact: true,
          onPressed: () => _goMonth(-1),
        ),
        Expanded(
          child: Text(
            l.yearMonthTitle('${_visibleMonth.year}', '${_visibleMonth.month}'),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: SpecTokens.t13.copyWith(
              fontWeight: FontWeight.w600,
              color: ds.ink,
            ),
          ),
        ),
        DsIconButton(
          icon: CupertinoIcons.chevron_right,
          compact: true,
          onPressed: () => _goMonth(1),
        ),
      ],
    );
  }

  Widget _weekdayRow(BuildContext context, DsColors ds) {
    final locale = Localizations.localeOf(context).toString();
    final label = DateFormat.E(locale);
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: ds.surface2,
        border: Border(
          left: BorderSide(color: ds.line),
          right: BorderSide(color: ds.line),
          top: BorderSide(color: ds.line),
        ),
      ),
      child: Row(
        children: [
          for (var weekday = 1; weekday <= 7; weekday++)
            Expanded(
              child: Center(
                child: Text(
                  label.format(DateTime(2026, 1, weekday + 4)),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: SpecTokens.t95.copyWith(color: ds.faint),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthGrid(BuildContext context, DsColors ds) {
    final locale = Localizations.localeOf(context).toString();
    final cells = _cells;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: ds.line),
          top: BorderSide(color: ds.line),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < 6; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    key: ValueKey('spec-day-${_iso(cells[row * 7 + col])}'),
                    child: _dayCell(
                      context,
                      ds,
                      locale,
                      cells[row * 7 + col],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DsColors ds,
    String locale,
    DateTime day,
  ) {
    final inMonth =
        day.year == _visibleMonth.year && day.month == _visibleMonth.month;
    final selected = DateUtils.isSameDay(day, _selected);
    final isToday = DateUtils.isSameDay(day, DateTime.now());
    final enabled = _isEnabled(day);
    final color = selected
        ? ds.surface
        : !enabled
        ? ds.faint.withValues(alpha: 0.38)
        : inMonth
        ? ds.ink2
        : ds.faint;
    final body = Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inMonth ? ds.surface : ds.surface2,
        border: Border(
          right: BorderSide(color: ds.line),
          bottom: BorderSide(color: ds.line),
        ),
      ),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(color: ds.ink, shape: BoxShape.circle)
            : isToday
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ds.ink),
              )
            : null,
        child: Text(
          '${day.day}',
          style: AppTypography.small.copyWith(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: color,
            fontFeatures: AppTypography.tabular,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      excludeSemantics: true,
      label: DateFormat.yMMMd(locale).format(day),
      child: enabled
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(day),
                child: body,
              ),
            )
          : body,
    );
  }
}

class SpecTimePickerDialog extends StatefulWidget {
  const SpecTimePickerDialog({super.key, required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<SpecTimePickerDialog> createState() => _SpecTimePickerDialogState();
}

class _SpecTimePickerDialogState extends State<SpecTimePickerDialog> {
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;

  @override
  void initState() {
    super.initState();
    _hourController = TextEditingController(
      text: widget.initialTime.hour.toString().padLeft(2, '0'),
    );
    _minuteController = TextEditingController(
      text: widget.initialTime.minute.toString().padLeft(2, '0'),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _confirm() {
    final hour = int.tryParse(_hourController.text);
    final minute = int.tryParse(_minuteController.text);
    Navigator.of(context).pop(
      TimeOfDay(
        hour: hour != null && hour >= 0 && hour < 24
            ? hour
            : widget.initialTime.hour,
        minute: minute != null && minute >= 0 && minute < 60
            ? minute
            : widget.initialTime.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    final fieldStyle = SpecTokens.t15.copyWith(
      fontSize: 18,
      color: ds.ink,
      fontFeatures: AppTypography.tabular,
    );
    return DsDialog(
      title: l.dueTime,
      width: 320,
      actions: [
        Expanded(
          child: DsButton(
            label: l.cancel,
            tone: DsButtonTone.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: DsButton(label: l.ok, expand: true, onPressed: _confirm),
        ),
      ],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            child: DsTextField(
              controller: _hourController,
              autofocus: true,
              style: fieldStyle,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: Text(
              ':',
              style: SpecTokens.t15.copyWith(fontSize: 18, color: ds.ink2),
            ),
          ),
          SizedBox(
            width: 72,
            child: DsTextField(
              controller: _minuteController,
              style: fieldStyle,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
            ),
          ),
        ],
      ),
    );
  }
}
