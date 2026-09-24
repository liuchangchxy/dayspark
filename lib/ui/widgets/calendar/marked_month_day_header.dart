import 'package:flutter/material.dart';
import 'package:kalender/kalender.dart';
import 'package:dayspark/domain/services/chinese_calendar_service.dart';
import 'package:dayspark/l10n/app_localizations.dart';

String solarTermLabel(AppLocalizations l, String zhName) {
  return switch (zhName) {
    '立春' => l.termLiChun,
    '雨水' => l.termYuShui,
    '惊蛰' => l.termJingZhe,
    '春分' => l.termChunFen,
    '清明' => l.termQingMing,
    '谷雨' => l.termGuYu,
    '立夏' => l.termLiXia,
    '小满' => l.termXiaoMan,
    '芒种' => l.termMangZhong,
    '夏至' => l.termXiaZhi,
    '小暑' => l.termXiaoShu,
    '大暑' => l.termDaShu,
    '立秋' => l.termLiQiu,
    '处暑' => l.termChuShu,
    '白露' => l.termBaiLu,
    '秋分' => l.termQiuFen,
    '寒露' => l.termHanLu,
    '霜降' => l.termShuangJiang,
    '立冬' => l.termLiDong,
    '小雪' => l.termXiaoXue,
    '大雪' => l.termDaXue,
    '冬至' => l.termDongZhi,
    '小寒' => l.termXiaoHan,
    '大寒' => l.termDaHan,
    _ => zhName,
  };
}

// Day-number cell used by the month grid: number (+ today highlight),
// statutory holiday / makeup-workday badge, and a solar-term micro-label
// under the number.
class MarkedMonthDayHeader extends StatelessWidget {
  final DateTime date;
  final MonthDayHeaderStyle? style;

  const MarkedMonthDayHeader({super.key, required this.date, this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final termZh = ChineseCalendarService.solarTerm(date);
    final holidayMark = ChineseCalendarService.holiday(date);
    final now = DateTime.now();
    final isToday =
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    final numberStyle =
        style?.numberTextStyle ??
        TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: theme.textTheme.bodyMedium?.color,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isToday)
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
                child: Text(
                  '${date.day}',
                  style: numberStyle.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Text('${date.day}', style: numberStyle, textAlign: TextAlign.center),
            if (holidayMark != null) ...[
              const SizedBox(width: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 0.5,
                ),
                decoration: BoxDecoration(
                  color: holidayMark.isWorkday
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  holidayMark.isWorkday
                      ? l.holidayWorkBadge
                      : l.holidayRestBadge,
                  style: TextStyle(
                    fontSize: 7,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: holidayMark.isWorkday
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onError,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (termZh != null)
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                solarTermLabel(l, termZh),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
