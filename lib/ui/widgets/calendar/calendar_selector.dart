import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// Calendar picker for the event forms.
///
/// Reads the shared [calendarsProvider] and hands the chosen id back to the
/// caller, so calendar state keeps its single owner instead of gaining a
/// second provider. A single calendar is not a choice, so the row collapses;
/// no calendar at all gets an inline notice with a way out.
class CalendarSelector extends ConsumerWidget {
  const CalendarSelector({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  final int? selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ref
        .watch(calendarsProvider)
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (calendars) {
            if (calendars.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.noCalendar,
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(calendarsProvider),
                      child: Text(l.retry),
                    ),
                  ],
                ),
              );
            }
            if (calendars.length == 1) {
              final onlyId = calendars.first.id;
              if (selectedId != onlyId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onChanged(onlyId);
                });
              }
              return const SizedBox.shrink();
            }

            final ids = calendars.map((c) => c.id).toSet();
            final effectiveId = (selectedId != null && ids.contains(selectedId))
                ? selectedId!
                : calendars.first.id;

            if (selectedId != effectiveId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onChanged(effectiveId);
              });
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.calendar,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<int>(
                    key: ValueKey<int>(effectiveId),
                    initialValue: effectiveId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    items: calendars
                        .map(
                          (calendar) => DropdownMenuItem<int>(
                            value: calendar.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: ColorUtils.parseHex(calendar.color),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    calendar.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id != null) onChanged(id);
                    },
                  ),
                ],
              ),
            );
          },
        );
  }
}
