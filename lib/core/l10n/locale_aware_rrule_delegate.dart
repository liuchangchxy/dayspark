import 'package:flutter/material.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/l10n/app_localizations.dart';

class LocaleAwareRRuleTextDelegate implements RRuleTextDelegate {
  final BuildContext context;

  LocaleAwareRRuleTextDelegate(this.context);

  bool get _isChinese {
    final locale = AppLocalizations.of(context)?.localeName;
    return locale != null && locale.startsWith('zh');
  }

  @override
  String get locale => _isChinese ? 'zh' : 'en';
  @override
  String get repeat => _isChinese ? '重复' : 'Repeat';
  @override
  String get day => _isChinese ? '天' : 'day';
  @override
  String get byDayInMonth => _isChinese ? '重复于' : 'On';
  @override
  String get byNthDayInMonth => _isChinese ? '每月的' : 'On the';
  @override
  String get every => _isChinese ? '每' : 'Every';
  @override
  String get of => _isChinese ? '的' : 'of';
  @override
  String get months => _isChinese ? '个月' : 'months';
  @override
  String get month => _isChinese ? '月' : 'month';
  @override
  String get weeks => _isChinese ? '周' : 'weeks';
  @override
  String get days => _isChinese ? '天' : 'days';
  @override
  String get date => _isChinese ? '日期' : 'date';
  @override
  String get on => _isChinese ? '在' : 'on';
  @override
  String get instances => _isChinese ? '次' : 'times';
  @override
  String get end => _isChinese ? '结束' : 'end';
  @override
  String get neverEnds => _isChinese ? '永不结束' : 'Never';
  @override
  String get endsAfter => _isChinese ? '结束后' : 'After';
  @override
  String get endsOnDate => _isChinese ? '结束于' : 'On date';
  @override
  String get excludeDate => _isChinese ? '排除日期' : 'Exclude';
  @override
  List<String> get daysInMonth => _isChinese
      ? ['第一个', '第二个', '第三个', '第四个', '最后一个']
      : ['1st', '2nd', '3rd', '4th', 'Last'];
  @override
  List<String> get periods => _isChinese
      ? ['每年', '每月', '每周', '每天', '从不']
      : ['Yearly', 'Monthly', 'Weekly', 'Daily', 'Never'];
}
