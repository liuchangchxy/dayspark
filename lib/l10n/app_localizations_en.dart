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
  String get dueTime => 'Time';

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
  String get notConfigured => 'Not configured';

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
  String get advancedFeatures => 'Advanced Features';

  @override
  String get attachments => 'Attachments';

  @override
  String get calendarData => 'Calendar data';

  @override
  String get add => 'Add';

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
  String get importExportDesc => 'Export calendar events and todos to .ics, or import from a .ics file.';

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
  String get noSubtaskSuggestions => 'No subtask suggestions available';

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
  String get allTasks => 'All Tasks';

  @override
  String get noDueDate => 'No due date';

  @override
  String get moveToToday => 'Move to today';

  @override
  String moveToTodayPrompt(int count) {
    return 'You have $count overdue todo(s). Move due dates to today?';
  }

  @override
  String movedToToday(int count) {
    return 'Moved $count todo(s) to today';
  }

  @override
  String get skip => 'Skip';

  @override
  String get pendingTodos => 'Pending';

  @override
  String get goToToday => 'Return to Today';

  @override
  String get ok => 'OK';

  @override
  String get defaultTab => 'Tab Order';

  @override
  String get defaultTabDesc => 'Choose the order of calendar and todos tabs';

  @override
  String get calendarFirst => 'Calendar First';

  @override
  String get todosFirst => 'Todos First';

  @override
  String get inbox => 'To-do Box';

  @override
  String get trash => 'Trash';

  @override
  String get emptyTrash => 'Empty Trash';

  @override
  String get restoreTodo => 'Restore';

  @override
  String get permanentDelete => 'Delete Permanently';

  @override
  String get trashEmpty => 'Trash is empty';

  @override
  String get moveToTrash => 'Move to Trash';

  @override
  String get confirmPermanentDelete => 'Permanently delete? This cannot be undone.';

  @override
  String get confirmEmptyTrash => 'Permanently delete all items in trash?';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get noDate => 'No date';

  @override
  String dateLabel(int month, int day) {
    return '$month/$day';
  }

  @override
  String get checkUpdate => 'Check for Updates';

  @override
  String get upToDate => 'Already up to date';

  @override
  String newVersionAvailable(String version) {
    return 'New version available: $version';
  }

  @override
  String get currentVersion => 'Current version';

  @override
  String get downloadUpdate => 'Download Update';

  @override
  String get starOnGithub => 'Star on GitHub';

  @override
  String get reportIssue => 'Report an Issue';

  @override
  String get aiProvider => 'Provider';

  @override
  String get customProvider => 'Custom';

  @override
  String get detectModels => 'Detect Models';

  @override
  String get detectingModels => 'Detecting...';

  @override
  String get noModelsFound => 'No models found';

  @override
  String get selectModel => 'Select Model';

  @override
  String get data => 'Data';

  @override
  String get tutorial => 'Tutorial';

  @override
  String get undo => 'Undo';

  @override
  String get deleted => 'Deleted';

  @override
  String snoozedFor(String duration) {
    return 'Snoozed for $duration';
  }

  @override
  String get markComplete => 'Mark Complete';

  @override
  String get snooze => 'Snooze';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get resetColor => 'Reset';

  @override
  String get feedback => 'Feedback';

  @override
  String get feedbackHint => 'Describe your feedback or bug report...';

  @override
  String get feedbackSubmit => 'Submit Feedback';

  @override
  String get feedbackCopied => 'Feedback copied to clipboard';

  @override
  String get whatsNew => 'What\'s New';

  @override
  String get changelogDismiss => 'OK';

  @override
  String get addEventShort => 'Add Event';

  @override
  String get addTodoShort => 'Add Todo';

  @override
  String get schedule => 'Schedule';

  @override
  String get breakDown => 'Break Down';

  @override
  String get eventReminder => 'Event Reminder';

  @override
  String get todoReminder => 'Todo Reminder';

  @override
  String get snoozedReminder => 'Snoozed reminder';

  @override
  String get eventStartingSoon => 'Event starting soon';

  @override
  String get taskDueSoon => 'Task due soon';

  @override
  String get addAttachment => 'Add attachment';

  @override
  String get editTag => 'Edit Tag';

  @override
  String get thirdPartyLicenses => 'Third-Party Licenses';

  @override
  String get security => 'Security';

  @override
  String get recurringDragDisabled => 'Recurring events cannot be moved by drag';

  @override
  String get eventMoved => 'Event moved';

  @override
  String get systemAlarm => 'System Alarm';

  @override
  String get systemAlarmDesc => 'Play alarm sound for reminders';

  @override
  String get exactAlarmTitle => 'Exact alarm permission';

  @override
  String get exactAlarmDesc => 'Grant it so reminders fire at the exact time';

  @override
  String get keyboardInput => 'Keyboard input';

  @override
  String get timeHint => 'HH:mm';

  @override
  String get aiParse => 'AI parse';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow System';

  @override
  String get languageZh => 'Chinese';

  @override
  String get languageEn => 'English';

  @override
  String get reminder => 'Reminder';

  @override
  String get subtasks => 'Subtasks';

  @override
  String get addSubtask => 'Add subtask';

  @override
  String get noSubtasks => 'No subtasks';

  @override
  String nMore(int count) {
    return '+$count more';
  }

  @override
  String get subtaskHint => 'Subtask text';

  @override
  String rateLimited(String repo) {
    return 'Rate limited. Visit github.com/$repo/releases to check manually.';
  }

  @override
  String get connectionTimedOut => 'Connection timed out. Check your network.';

  @override
  String updateCheckFailed(String repo) {
    return 'Update check failed. Visit github.com/$repo/releases.';
  }

  @override
  String get gitHub => 'GitHub';

  @override
  String get openTodoDetails => 'Open todo details';

  @override
  String get highPriority => 'High priority';

  @override
  String get mediumPriority => 'Medium priority';

  @override
  String get markIncomplete => 'Mark incomplete';

  @override
  String tagWith(String name) {
    return 'Tag: $name';
  }

  @override
  String get openEventDetails => 'Open event details';

  @override
  String get previousPeriod => 'Previous';

  @override
  String get nextPeriod => 'Next';
}
