import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/core/l10n/locale_aware_rrule_delegate.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_pickers.dart';
import 'package:dayspark/ui/widgets/schedule/schedule_row.dart';

/// The shapes a rule can take at the top level. Anything the library can build
/// beyond these is reachable, but only through the advanced sheet — so the
/// common answer stays four taps and never shows a rule string.
enum RepeatMode { never, daily, weekly, monthly, yearly, custom }

RepeatMode repeatModeFor(String? rrule) {
  if (rrule == null || rrule.isEmpty) return RepeatMode.never;
  final rule = rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;
  for (final entry in const {
    'FREQ=DAILY': RepeatMode.daily,
    'FREQ=WEEKLY': RepeatMode.weekly,
    'FREQ=MONTHLY': RepeatMode.monthly,
    'FREQ=YEARLY': RepeatMode.yearly,
  }.entries) {
    // INTERVAL=1 and no BY* parts is what the four one-tap choices produce;
    // anything richer is a custom rule and must be edited as one.
    if (!rule.startsWith(entry.key)) continue;
    final rest = rule.substring(entry.key.length);
    final plain =
        !rest.contains('INTERVAL=') &&
        !rest.contains('BY') &&
        !rest.contains('COUNT') &&
        !rest.contains('UNTIL');
    return plain ? entry.value : RepeatMode.custom;
  }
  return RepeatMode.custom;
}

String repeatRuleFor(RepeatMode mode) => switch (mode) {
  RepeatMode.never => '',
  RepeatMode.daily => 'FREQ=DAILY',
  RepeatMode.weekly => 'FREQ=WEEKLY',
  RepeatMode.monthly => 'FREQ=MONTHLY',
  RepeatMode.yearly => 'FREQ=YEARLY',
  RepeatMode.custom => '',
};

/// One row that answers "does this repeat?". Opens a sheet; the row itself only
/// ever prints a localized phrase.
///
/// The date a series counts from belongs to the rule, not to the todo's main
/// fields: it is asked once, inside the repeat sheet, and only when something
/// repeats.
class RepeatRow extends ConsumerWidget {
  const RepeatRow({
    super.key,
    required this.rrule,
    required this.onChanged,
    required this.anchorDate,
    this.anchorLabel,
    this.startDate,
    this.onStartDateChanged,
    this.needsDate = false,
  });

  final String? rrule;
  final ValueChanged<String?> onChanged;

  /// The date the series counts from — the deadline, or an explicit start date
  /// once the user picks one.
  final DateTime? anchorDate;

  final String? anchorLabel;

  /// The explicit start the user chose, if any.
  final DateTime? startDate;
  final ValueChanged<DateTime?>? onStartDateChanged;

  /// True when the todo has no date at all yet, so there is nothing to repeat
  /// from.
  final bool needsDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return ScheduleRow(
      label: l.recurrenceRule,
      value: describeRepeat(context, rrule),
      placeholder: rrule == null,
      onTap: () => _openSheet(context, l, ref),
      clearTooltip: l.repeatNever,
      onClear: rrule == null ? null : () => onChanged(null),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    AppLocalizations l,
    WidgetRef ref,
  ) async {
    final anchor = anchorDate;
    if (anchor == null || needsDate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.repeatNeedsDate)));
      return;
    }
    final result = await showModalBottomSheet<RepeatChoice>(
      context: context,
      builder: (ctx) => _RepeatSheet(
        rrule: rrule,
        anchorDate: anchor,
        explicitStart: startDate,
        anchorLabel: anchorLabel,
        // Only a series with no date of its own needs this; the ordinary form
        // takes its anchor from the deadline and must not ask twice.
        onPickStart: startDate == null ? null : onStartDateChanged,
      ),
    );
    if (result == null) return;
    onChanged(result.rrule.isEmpty ? null : result.rrule);
  }
}

/// What the repeat sheet came back with. A plain rule string: the sheet is the
/// only place that knows about RRULE syntax, and it never shows it to the user.
class RepeatChoice {
  const RepeatChoice(this.rrule);

  final String rrule;
}

/// Human phrasing for a rule. A rule with an end date or a custom interval is
/// still fundamentally daily/weekly/…, so the row says that rather than
/// retreating to "Custom"; the sheet is where the details live.
///
/// The rule string is a machine format and never reaches the user: every part
/// that changes what the series actually does — interval, weekdays, the end —
/// is spelled out, because "Every week" for a Mon/Wed/Fri series would be a
/// lie the user cannot see through.
String describeRepeat(BuildContext context, String? rrule) {
  final l = AppLocalizations.of(context)!;
  if (rrule == null || rrule.trim().isEmpty) return l.repeatNever;
  final rule = rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;
  final parts = <String, String>{};
  for (final part in rule.split(';')) {
    final split = part.indexOf('=');
    if (split <= 0) continue;
    parts[part.substring(0, split).toUpperCase()] = part.substring(split + 1);
  }

  final freq = parts['FREQ']?.toUpperCase();
  final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
  final days = _weekdayNames(context, parts['BYDAY']);

  final String base;
  switch (freq) {
    case 'DAILY':
      base = interval > 1 ? l.repeatEveryNDays(interval) : l.repeatDaily;
    case 'WEEKLY':
      if (days.isNotEmpty) {
        final label = days.join(', ');
        base = interval > 1
            ? l.repeatEveryNWeekdays(label, interval)
            : l.repeatOnDays(label);
      } else {
        base = interval > 1 ? l.repeatEveryNWeeks(interval) : l.repeatWeekly;
      }
    case 'MONTHLY':
      final day = int.tryParse(parts['BYMONTHDAY'] ?? '');
      if (interval > 1) {
        base = l.repeatEveryNMonths(interval);
      } else {
        base = day != null ? l.repeatMonthlyOnDay(day) : l.repeatMonthly;
      }
    case 'YEARLY':
      base = interval > 1 ? l.repeatEveryNYears(interval) : l.repeatYearly;
    default:
      return l.repeatCustom;
  }

  final count = int.tryParse(parts['COUNT'] ?? '');
  if (count != null && count > 0) {
    return '$base · ${l.repeatEndsAfter(count)}';
  }
  final until = _parseUntil(parts['UNTIL']);
  if (until != null) {
    return '$base · ${l.repeatUntil(_formatRuleDate(context, until))}';
  }
  return base;
}

/// BYDAY carries weekday codes (`MO,TU`) and an optional ordinal (`2TU`). The
/// ordinal is not something the app can create, so it is dropped rather than
/// rendered as noise; the weekdays themselves are what the user recognises.
List<String> _weekdayNames(BuildContext context, String? byDay) {
  if (byDay == null || byDay.isEmpty) return const [];
  const codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  final locale = Localizations.localeOf(context).toString();
  final names = <String>[];
  for (final entry in byDay.split(',')) {
    final code = entry.trim().toUpperCase();
    final index = codes.indexWhere(code.endsWith);
    if (index < 0) continue;
    // 2024-01-01 was a Monday, so index maps straight onto that week.
    final day = DateTime(2024, 1, 1 + index);
    names.add(DateFormat.E(locale).format(day));
  }
  return names;
}

DateTime? _parseUntil(String? value) {
  if (value == null || value.isEmpty) return null;
  final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(value);
  if (compact != null) {
    return DateTime(
      int.parse(compact.group(1)!),
      int.parse(compact.group(2)!),
      int.parse(compact.group(3)!),
    );
  }
  return DateTime.tryParse(value);
}

String _formatRuleDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(value);

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({
    required this.rrule,
    required this.anchorDate,
    this.anchorLabel,
    this.explicitStart,
    this.onPickStart,
  });

  final String? rrule;
  final DateTime anchorDate;
  final String? anchorLabel;

  /// An explicit start date, when the user has chosen one. Null means the
  /// series counts from the todo's single date.
  final DateTime? explicitStart;

  /// Set when the sheet should offer "which day does it repeat from" — the
  /// anchor the app cannot infer, notably for an imported legacy rule.
  final ValueChanged<DateTime>? onPickStart;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late RepeatMode _mode = repeatModeFor(widget.rrule);
  late String _customRule = widget.rrule ?? '';
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l.recurrenceRule, style: AppTypography.title),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: l.close,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.onPickStart != null)
                      _RepeatOption(
                        label:
                            '${l.legacyRepeatFrom}: '
                            '${formatDeadline(context, widget.explicitStart ?? widget.anchorDate)}',
                        selected: false,
                        trailing: const Icon(CupertinoIcons.calendar, size: 14),
                        onTap: () async {
                          final picked = await pickDeadline(
                            context,
                            initial: widget.explicitStart ?? widget.anchorDate,
                          );
                          if (picked != null) {
                            widget.onPickStart!(picked);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                      ),
                    for (final mode in RepeatMode.values)
                      if (mode != RepeatMode.custom)
                        _RepeatOption(
                          label: _labelFor(l, mode),
                          selected: _mode == mode,
                          onTap: () => setState(() {
                            _mode = mode;
                            _showAdvanced = false;
                          }),
                        ),
                    _RepeatOption(
                      label: l.repeatCustom,
                      selected: _mode == RepeatMode.custom,
                      trailing: const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 14,
                      ),
                      onTap: () => setState(() {
                        _mode = RepeatMode.custom;
                        _showAdvanced = true;
                      }),
                    ),
                    if (_showAdvanced) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        child: RRuleGenerator(
                          localeBuilder: (_) =>
                              LocaleAwareRRuleTextDelegate(context),
                          config: RRuleGeneratorConfig(),
                          initialRRule: _customRule,
                          withExcludeDates: false,
                          onChange: (value) =>
                              setState(() => _customRule = value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(RepeatChoice(_resultingRule())),
                child: Text(l.done),
              ),
            ),
            if (widget.anchorLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  widget.anchorLabel!,
                  style: AppTypography.caption.copyWith(
                    color: context.semantic.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _resultingRule() =>
      _mode == RepeatMode.custom ? _customRule : repeatRuleFor(_mode);

  String _labelFor(AppLocalizations l, RepeatMode mode) => switch (mode) {
    RepeatMode.never => l.repeatNever,
    RepeatMode.daily => l.repeatDaily,
    RepeatMode.weekly => l.repeatWeekly,
    RepeatMode.monthly => l.repeatMonthly,
    RepeatMode.yearly => l.repeatYearly,
    RepeatMode.custom => l.repeatCustom,
  };
}

class _RepeatOption extends StatelessWidget {
  const _RepeatOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.body.copyWith(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else if (selected)
                Icon(
                  CupertinoIcons.checkmark,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
