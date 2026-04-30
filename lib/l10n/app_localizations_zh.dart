// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '灵光';

  @override
  String get calendar => '日历';

  @override
  String get todos => '待办';

  @override
  String get settings => '设置';

  @override
  String get search => '搜索';

  @override
  String get newEvent => '新建日程';

  @override
  String get newTodo => '新建待办';

  @override
  String get editEvent => '编辑日程';

  @override
  String get editTodo => '编辑待办';

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get remove => '移除';

  @override
  String get create => '创建';

  @override
  String get title => '标题';

  @override
  String get description => '备注';

  @override
  String get location => '地点';

  @override
  String get startDate => '开始日期';

  @override
  String get endDate => '结束日期';

  @override
  String get dueDate => '截止日期';

  @override
  String get allDay => '全天';

  @override
  String get priority => '优先级';

  @override
  String get priorityNone => '无';

  @override
  String get priorityLow => '低';

  @override
  String get priorityMedium => '中';

  @override
  String get priorityHigh => '高';

  @override
  String get tags => '标签';

  @override
  String get manageTags => '管理标签';

  @override
  String get createTag => '创建标签';

  @override
  String get deleteTag => '删除标签';

  @override
  String get tagName => '标签名称';

  @override
  String get noTags => '暂无标签';

  @override
  String get caldavAccount => 'CalDAV 账户';

  @override
  String get addCalDav => '添加 CalDAV 账户';

  @override
  String get editCalDav => '编辑 CalDAV 账户';

  @override
  String get removeAccount => '移除账户';

  @override
  String get serverUrl => '服务器地址';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get syncNow => '立即同步';

  @override
  String get syncing => '同步中…';

  @override
  String lastSync(String time) {
    return '上次同步：$time';
  }

  @override
  String get notConfigured => '未配置';

  @override
  String connected(String user) {
    return '已连接为 $user';
  }

  @override
  String get aiConfig => 'AI 配置';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get baseUrl => '接口地址';

  @override
  String get model => '模型';

  @override
  String get aiHint => '让我帮你创建日程或待办';

  @override
  String get aiExample => '比如「明天下午3点和张三开会」';

  @override
  String get aiNotConfigured => 'AI 未配置';

  @override
  String get aiGoToSettings => '前往「设置 > AI」配置你的 API 密钥';

  @override
  String get notifications => '通知';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色模式';

  @override
  String get themeDark => '深色模式';

  @override
  String get about => '关于';

  @override
  String get noPendingTodos => '暂无待办';

  @override
  String get tapToCreate => '点击 + 新建一个';

  @override
  String get noResults => '没有找到结果';

  @override
  String get enterTitle => '请输入标题';

  @override
  String get noCalendar => '没有可用的日历，请先在设置中添加。';

  @override
  String get eventSaved => '日程已保存';

  @override
  String get todoSaved => '待办已保存';

  @override
  String get confirmDelete => '确定要删除吗？';

  @override
  String get clearChat => '清空对话';

  @override
  String get typeMessage => '输入消息…';

  @override
  String get today => '今天';

  @override
  String get day => '日';

  @override
  String get week => '周';

  @override
  String get month => '月';

  @override
  String get overdue => '已逾期';

  @override
  String get tomorrow => '明天';

  @override
  String get notSet => '未设置';

  @override
  String get events => '日程';

  @override
  String get typeToSearch => '输入关键词搜索';

  @override
  String get eventCreated => '日程已创建';

  @override
  String get todoCreated => '待办已创建';

  @override
  String get importExport => '导入/导出';

  @override
  String get export => '导出';

  @override
  String get import => '导入';

  @override
  String get defaultReminderTimes => '默认提醒时间';

  @override
  String get advancedFeatures => '高级功能';

  @override
  String get attachments => '附件';

  @override
  String get calendarData => '日历数据';

  @override
  String get caldavAccounts => 'CalDAV 账户';

  @override
  String get noAccounts => '暂无已配置的账户';

  @override
  String get addAccount => '添加 CalDAV 账户';

  @override
  String get accountName => '账户名称';

  @override
  String get accountNameHint => '比如：工作、个人';

  @override
  String removeAccountConfirm(String name) {
    return '确定移除「$name」及其所有日历吗？';
  }

  @override
  String get removeAccountTitle => '移除账户';

  @override
  String get add => '添加';

  @override
  String mcpServerError(String error) {
    return 'MCP 服务器出错：$error';
  }

  @override
  String syncFailed(String error) {
    return '同步失败：$error';
  }

  @override
  String exportedTo(String path) {
    return '已导出到 $path';
  }

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get noCalendarToImport => '没有可用的日历来导入数据';

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String importedResult(int events, int todos) {
    return '已导入 $events 条日程和 $todos 条待办';
  }

  @override
  String get importExportDesc => '将日程和待办导出为 .ics 文件，或从 .ics 文件导入。';

  @override
  String error(String error) {
    return '出错了：$error';
  }

  @override
  String get endBeforeStart => '结束时间必须晚于开始时间';

  @override
  String get aiNotConfiguredHint => 'AI 未配置，请前往「设置 > AI」进行配置';

  @override
  String aiError(String error) {
    return 'AI 出错：$error';
  }

  @override
  String deleteEventConfirm(String title) {
    return '确定删除「$title」吗？';
  }

  @override
  String get noTimeSlots => '暂无可用的时间建议';

  @override
  String get suggestedTimeSlots => '推荐时间段';

  @override
  String schedulingFailed(String error) {
    return '排程失败：$error';
  }

  @override
  String get noSubtasks => '暂无子任务建议';

  @override
  String get taskBreakdown => '任务拆分';

  @override
  String get todoCreatedShort => '待办已创建';

  @override
  String failedCreateTodo(String error) {
    return '创建待办失败：$error';
  }

  @override
  String breakdownFailed(String error) {
    return '拆分失败：$error';
  }

  @override
  String get eventCreatedShort => '日程已创建';

  @override
  String failedAction(String error) {
    return '操作失败：$error';
  }

  @override
  String get noAttachments => '暂无附件';

  @override
  String get completed => '已完成';

  @override
  String get dayAfterTomorrow => '后天';

  @override
  String get nextWeek => '下周';

  @override
  String get custom => '自定义';

  @override
  String get todayTodo => '今日待办';

  @override
  String get allTasks => '全部任务';

  @override
  String get upcoming => '即将到期';

  @override
  String get noDueDate => '无截止日期';

  @override
  String overdueCount(Object count) {
    return '$count 条已逾期';
  }

  @override
  String get moveToToday => '移到今天';

  @override
  String moveToTodayPrompt(Object count) {
    return '有 $count 条待办已逾期，是否将截止日期移到今天？';
  }

  @override
  String movedToToday(Object count) {
    return '已将 $count 条待办移到今天';
  }

  @override
  String get skip => '跳过';

  @override
  String get completedRecently => '近期已完成';

  @override
  String get pendingTodos => '待处理';

  @override
  String get goToToday => '回到今天';

  @override
  String weekOfMonth(int week) {
    return '第$week周';
  }

  @override
  String get ok => '确定';

  @override
  String get defaultTab => '标签页顺序';

  @override
  String get defaultTabDesc => '选择日历和待办的显示顺序';

  @override
  String get calendarFirst => '日历在前';

  @override
  String get todosFirst => '待办在前';

  @override
  String get lunarCalendar => '农历';

  @override
  String get lunarCalendarDesc => '在日历中显示中国农历日期';

  @override
  String get inbox => '待办箱';

  @override
  String get trash => '回收站';

  @override
  String get emptyTrash => '清空回收站';

  @override
  String get restoreTodo => '恢复';

  @override
  String get permanentDelete => '永久删除';

  @override
  String get trashEmpty => '回收站为空';

  @override
  String get moveToTrash => '移到回收站';

  @override
  String get confirmPermanentDelete => '永久删除？此操作无法撤销。';

  @override
  String get confirmEmptyTrash => '确定永久删除回收站中的所有项目？';

  @override
  String get yesterday => '昨天';

  @override
  String get noDate => '无日期';

  @override
  String dateLabel(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get checkUpdate => '检查更新';

  @override
  String get upToDate => '已是最新版本';

  @override
  String newVersionAvailable(String version) {
    return '发现新版本：$version';
  }

  @override
  String get currentVersion => '当前版本';

  @override
  String get downloadUpdate => '下载更新';

  @override
  String get starOnGithub => '在 GitHub 上 Star';

  @override
  String get reportIssue => '反馈问题';

  @override
  String get setupGuide => '配置教程';

  @override
  String get aiProvider => '服务商';

  @override
  String get customProvider => '自定义';

  @override
  String get detectModels => '探测模型';

  @override
  String get detectingModels => '探测中…';

  @override
  String get noModelsFound => '未找到模型';

  @override
  String get selectModel => '选择模型';

  @override
  String get data => '数据';

  @override
  String get tutorial => '教程';

  @override
  String get undo => '撤销';

  @override
  String get deleted => '已删除';

  @override
  String get markedComplete => '已标记完成';

  @override
  String snoozedFor(String duration) {
    return '已延后 $duration';
  }

  @override
  String get oneHour => '1 小时';

  @override
  String get markComplete => '标记完成';

  @override
  String get snooze => '延后';

  @override
  String get themeColor => '主题色';

  @override
  String get resetColor => '重置';

  @override
  String get feedback => '反馈';

  @override
  String get feedbackHint => '描述你的反馈或 Bug…';

  @override
  String get feedbackSubmit => '提交反馈';

  @override
  String get feedbackCopied => '反馈已复制到剪贴板';

  @override
  String get whatsNew => '更新内容';

  @override
  String get changelogDismiss => '确定';
}
