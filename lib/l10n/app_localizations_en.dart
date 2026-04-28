// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DaySpark';

  @override
  String get calendar => 'Calendar';

  @override
  String get todos => 'Todos';

  @override
  String get settings => 'Settings';

  @override
  String get search => 'Search';

  @override
  String get newEvent => 'New Event';

  @override
  String get newTodo => 'New Todo';

  @override
  String get editEvent => 'Edit Event';

  @override
  String get editTodo => 'Edit Todo';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get remove => 'Remove';

  @override
  String get create => 'Create';

  @override
  String get title => 'Title';

  @override
  String get description => 'Description';

  @override
  String get location => 'Location';

  @override
  String get startDate => 'Starts at';

  @override
  String get endDate => 'Ends at';

  @override
  String get dueDate => 'Due date';

  @override
  String get allDay => 'All day';

  @override
  String get priority => 'Priority';

  @override
  String get priorityNone => 'None';

  @override
  String get priorityLow => 'Low';

  @override
  String get priorityMedium => 'Medium';

  @override
  String get priorityHigh => 'High';

  @override
  String get tags => 'Tags';

  @override
  String get manageTags => 'Manage Tags';

  @override
  String get createTag => 'Create Tag';

  @override
  String get deleteTag => 'Delete Tag';

  @override
  String get tagName => 'Tag name';

  @override
  String get noTags => 'No tags yet';

  @override
  String get caldavAccount => 'CalDAV Account';

  @override
  String get addCalDav => 'Add CalDAV Account';

  @override
  String get editCalDav => 'Edit CalDAV Account';

  @override
  String get removeAccount => 'Remove Account';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get syncNow => 'Sync Now';

  @override
  String get syncing => 'Syncing...';

  @override
  String lastSync(String time) {
    return 'Last sync: $time';
  }

  @override
  String get notConfigured => 'Not configured';

  @override
  String connected(String user) {
    return 'Connected as $user';
  }

  @override
  String get aiConfig => 'AI Configuration';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get apiKey => 'API Key';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get model => 'Model';

  @override
  String get aiHint => 'Ask me to create events or todos';

  @override
  String get aiExample => 'e.g. \"Meeting with John tomorrow 3pm\"';

  @override
  String get aiNotConfigured => 'AI is not configured';

  @override
  String get aiGoToSettings => 'Go to Settings > AI to configure your API key';

  @override
  String get notifications => 'Notifications';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System Default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get about => 'About';

  @override
  String get noPendingTodos => 'No pending todos';

  @override
  String get tapToCreate => 'Tap + to create one';

  @override
  String get noResults => 'No results';

  @override
  String get enterTitle => 'Please enter a title';

  @override
  String get noCalendar => 'No calendar available. Add one in Settings.';

  @override
  String get eventSaved => 'Event saved';

  @override
  String get todoSaved => 'Todo saved';

  @override
  String get confirmDelete => 'Are you sure you want to delete?';

  @override
  String get clearChat => 'Clear chat';

  @override
  String get typeMessage => 'Type a message...';

  @override
  String get today => 'Today';

  @override
  String get day => 'Day';

  @override
  String get week => 'Week';

  @override
  String get month => 'Month';

  @override
  String get overdue => 'Overdue';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get notSet => 'Not set';

  @override
  String get events => 'Events';

  @override
  String get typeToSearch => 'Type to search';

  @override
  String get eventCreated => 'Event created';

  @override
  String get todoCreated => 'Todo created';

  @override
  String get importExport => 'Import / Export';

  @override
  String get export => 'Export';

  @override
  String get import => 'Import';

  @override
  String get defaultReminderTimes => 'Default reminder times';

  @override
  String get advancedFeatures => 'Advanced Features';

  @override
  String get attachments => 'Attachments';

  @override
  String get calendarData => 'Calendar data';

  @override
  String get caldavAccounts => 'CalDAV Accounts';

  @override
  String get noAccounts => 'No accounts configured yet.';

  @override
  String get addAccount => 'Add CalDAV Account';

  @override
  String get accountName => 'Account Name';

  @override
  String get accountNameHint => 'e.g. Work, Personal';

  @override
  String removeAccountConfirm(String name) {
    return 'Remove \"$name\" and all its calendars?';
  }

  @override
  String get removeAccountTitle => 'Remove Account';

  @override
  String get add => 'Add';

  @override
  String mcpServerError(String error) {
    return 'MCP Server error: $error';
  }

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String exportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get noCalendarToImport => 'No calendar found to import into';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String importedResult(int events, int todos) {
    return 'Imported $events event(s) and $todos todo(s)';
  }

  @override
  String get importExportDesc =>
      'Export calendar events and todos to .ics, or import from a .ics file.';

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get endBeforeStart => 'End time must be after start time';

  @override
  String get aiNotConfiguredHint => 'AI not configured. Go to Settings > AI.';

  @override
  String aiError(String error) {
    return 'AI error: $error';
  }

  @override
  String deleteEventConfirm(String title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get noTimeSlots => 'No time slot suggestions available';

  @override
  String get suggestedTimeSlots => 'Suggested Time Slots';

  @override
  String schedulingFailed(String error) {
    return 'Scheduling failed: $error';
  }

  @override
  String get noSubtasks => 'No subtask suggestions available';

  @override
  String get taskBreakdown => 'Task Breakdown';

  @override
  String get todoCreatedShort => 'Todo created';

  @override
  String failedCreateTodo(String error) {
    return 'Failed to create todo: $error';
  }

  @override
  String breakdownFailed(String error) {
    return 'Breakdown failed: $error';
  }

  @override
  String get eventCreatedShort => 'Event created';

  @override
  String failedAction(String error) {
    return 'Failed: $error';
  }

  @override
  String get noAttachments => 'No attachments';

  @override
  String get completed => 'Completed';

  @override
  String get dayAfterTomorrow => 'Day after';

  @override
  String get nextWeek => 'Next week';

  @override
  String get custom => 'Custom';

  @override
  String get todayTodo => 'Today';

  @override
  String get allTasks => 'All Tasks';

  @override
  String get upcoming => 'Upcoming';

  @override
  String get noDueDate => 'No due date';

  @override
  String overdueCount(Object count) {
    return '$count overdue';
  }

  @override
  String get moveToToday => 'Move to today';

  @override
  String moveToTodayPrompt(Object count) {
    return 'You have $count overdue todo(s). Move due dates to today?';
  }

  @override
  String movedToToday(Object count) {
    return 'Moved $count todo(s) to today';
  }

  @override
  String get skip => 'Skip';

  @override
  String get completedRecently => 'Recently completed';

  @override
  String get pendingTodos => 'Pending';

  @override
  String get goToToday => 'Return to Today';

  @override
  String weekOfMonth(int week, String month) {
    return 'Week $week of $month';
  }

  @override
  String get ok => 'OK';
}
