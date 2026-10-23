import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/core/l10n/locale_aware_rrule_delegate.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/l10n/app_localizations.dart';
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
class RepeatRow extends StatelessWidget {
  const RepeatRow({
    super.key,
    required this.rrule,
    required this.onChanged,
    required this.anchorDate,
    this.anchorLabel,
  });

  final String? rrule;
  final ValueChanged<String?> onChanged;

  /// The date the series counts from. Null means the user has not given the
  /// todo a date yet, so there is nothing to repeat from.
  final DateTime? anchorDate;

  final String? anchorLabel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ScheduleRow(
      label: l.recurrenceRule,
      value: describeRepeat(context, rrule),
      placeholder: rrule == null,
      onTap: () => _openSheet(context, l),
    );
  }

  Future<void> _openSheet(BuildContext context, AppLocalizations l) async {
    if (anchorDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.repeatNeedsDate)),
      );
      return;
    }
    final result = await showModalBottomSheet<RepeatChoice>(
      context: context,
      builder: (ctx) => _RepeatSheet(
        rrule: rrule,
        anchorDate: anchorDate!,
        anchorLabel: anchorLabel,
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
String describeRepeat(BuildContext context, String? rrule) {
  final l = AppLocalizations.of(context)!;
  if (rrule == null || rrule.trim().isEmpty) return l.repeatNever;
  final rule = rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;
  final freq = RegExp(r'FREQ=([A-Z]+)').firstMatch(rule)?.group(1);
  return switch (freq) {
    'DAILY' => l.repeatDaily,
    'WEEKLY' => l.repeatWeekly,
    'MONTHLY' => l.repeatMonthly,
    'YEARLY' => l.repeatYearly,
    _ => l.repeatCustom,
  };
}

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({
    required this.rrule,
    required this.anchorDate,
    this.anchorLabel,
  });

  final String? rrule;
  final DateTime anchorDate;
  final String? anchorLabel;

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
                          onChange: (value) => setState(() => _customRule = value),
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
                onPressed: () => Navigator.of(
                  context,
                ).pop(RepeatChoice(_resultingRule())),
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
