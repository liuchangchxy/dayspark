import 'package:rrule_generator/rrule_generator.dart';

class CorrectChineseTextDelegate implements RRuleTextDelegate {
  const CorrectChineseTextDelegate();

  @override
  String get locale => 'zh';
  @override
  String get repeat => '重复';
  @override
  String get day => '天';
  @override
  String get byDayInMonth => '重复于';
  @override
  String get byNthDayInMonth => '每月的';
  @override
  String get every => '每';
  @override
  String get of => '的';
  @override
  String get months => '个月';
  @override
  String get month => '月';
  @override
  String get weeks => '周';
  @override
  String get days => '天';
  @override
  String get date => '日期';
  @override
  String get on => '在';
  @override
  String get instances => '次';
  @override
  String get end => '结束';
  @override
  String get neverEnds => '永不结束';
  @override
  String get endsAfter => '结束后';
  @override
  String get endsOnDate => '结束于';
  @override
  String get excludeDate => '排除日期';
  @override
  List<String> get daysInMonth => ['第一个', '第二个', '第三个', '第四个', '最后一个'];
  @override
  List<String> get periods => ['每年', '每月', '每周', '每天', '从不'];
}
