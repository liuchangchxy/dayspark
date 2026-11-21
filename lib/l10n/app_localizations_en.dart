// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get preview => 'Preview';

  @override
  String get legacyRepeatFrom => 'Repeat starts';

  @override
  String get legacyRecurrencePreview => 'Next occurrences (preview)';

  @override
  String get selectTodoOccurrence => 'Select occurrence';

  @override
  String get earlierThirtyDays => 'Earlier 30 days';

  @override
  String get newerOccurrences => 'Newer';

  @override
  String get legacyRecurrenceRequiresConfirmation => 'Confirm this recurrence before scheduling an occurrence.';

  @override
  String get unsupportedRecurrence => 'This recurrence rule cannot be expanded for scheduling.';

  @override
  String get unsupportedLegacyRecurrence => 'This imported recurrence rule uses unsupported or invalid syntax and cannot be scheduled.';

  @override
  String get noOccurrencesAvailable => 'No occurrences are available in the next 90 days.';

  @override
  String get occurrenceWindowHint => 'Showing matches only within the next 90 days. The series may continue outside this window.';

  @override
  String get orphanTaskAllocation => 'Its recurring occurrence no longer exists. The scheduled time is retained.';

  @override
  String get confirmLegacyRecurrenceTitle => 'Confirm repeating task';

  @override
  String get confirmLegacyRecurrenceBody => 'This repeating task was imported before the app recorded which day it repeats from. Pick that day once; the app will work the rest out.';

  @override
  String get legacyAnchorEvidence => 'Stored date and time';

  @override
  String get dateOnly => 'Date only';

  @override
  String get dateAndTime => 'Date and time';

  @override
  String get recurrenceRule => 'Repeat rule';

  @override
  String get recurrenceZoneBelongsToSeries => 'This time zone belongs to the whole series.';

  @override
  String get recurrenceAnchor => 'Series anchor';

  @override
  String get recurrenceEditAllocationWarning => 'Changing the repeat rule, anchor, or time zone will not move existing scheduled time blocks. Some may no longer match this series.';

  @override
  String get recurrenceTimezoneHorizonError => 'The current time-zone data cannot calculate this date range yet.';

  @override
  String get recurrenceOccurrenceLimitError => 'There are more matching occurrences than this selector can show. Narrow the date range.';

  @override
  String get appName => 'DaySpark';

  @override
  String get calendarUnavailable => 'Calendar unavailable. Please choose another calendar.';

  @override
  String get loadMore => 'Load More';

  @override
  String get allCalendars => 'All Calendars';

  @override
  String get targetCalendar => 'Target Calendar';

  @override
  String get manageCalendars => 'Manage Calendars';

  @override
  String get myCalendars => 'My Calendars';

  @override
  String get allTags => 'All Tags';

  @override
  String categoryCount(int count) {
    return '$count total';
  }

  @override
  String get newCalendar => 'New Calendar';

  @override
  String get navigationError => 'Navigation Error';

  @override
  String pageNotFound(String uri) {
    return 'Page not found or failed to load: $uri';
  }

  @override
  String get returnToHome => 'Return to Home';

  @override
  String get eventNotFound => 'Event Not Found';

  @override
  String get missingEventParam => 'This link did not carry an event. Open it from the calendar instead.';

  @override
  String get todoNotFound => 'Task Not Found';

  @override
  String get missingTodoParam => 'This link did not carry a task. Open it from a list instead.';

  @override
  String get editCalendar => 'Edit Calendar';

  @override
  String get deleteCalendar => 'Delete Calendar';

  @override
  String get calendarName => 'Calendar Name';

  @override
  String get cannotDeleteOnlyCalendar => 'Cannot delete the only calendar';

  @override
  String get calendar => 'Calendar';

  @override
  String get todos => 'Tasks';

  @override
  String get settings => 'Settings';

  @override
  String get search => 'Search';

  @override
  String get searchTasksAndEvents => 'Search tasks and events';

  @override
  String get newEvent => 'New Event';

  @override
  String get newTodo => 'New Task';

  @override
  String get newItem => 'New';

  @override
  String get editEvent => 'Edit Event';

  @override
  String get editTodo => 'Edit Task';

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
  String get locationHint => 'Add location';

  @override
  String get startDate => 'Repeat starts';

  @override
  String get startAfterDeadline => 'Starts at has to come before the deadline.';

  @override
  String get endDate => 'Ends at';

  @override
  String get dueDate => 'Due date';

  @override
  String get dueTime => 'Time';

  @override
  String get allDay => 'All day';

  @override
  String get plannedShort => 'Planned';

  @override
  String overdueDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days late',
      one: '1 day late',
    );
    return '$_temp0';
  }

  @override
  String dayItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String deadlineLane(int count) {
    return 'Due (no time block) · $count';
  }

  @override
  String get noPlansDay => 'Nothing planned';

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
  String get aiEnable => 'Enabled';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get openAssistant => 'Open assistant';

  @override
  String get apiKey => 'API Key';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get model => 'Model';

  @override
  String get aiHint => 'Ask me to create events or tasks';

  @override
  String get aiExample => 'e.g. \"Meeting with John tomorrow 3pm\"';

  @override
  String get aiNotConfigured => 'AI is not configured';

  @override
  String get aiGoToSettings => 'Go to Settings > AI to configure your API key';

  @override
  String get notifications => 'Notifications & reminders';

  @override
  String get appearance => 'General';

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
  String get noPendingTodos => 'No pending tasks';

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
  String get upcoming => 'Upcoming';

  @override
  String get quickAdd => 'Quick add';

  @override
  String get notSynced => 'Not synced';

  @override
  String get completedLabel => 'Done';

  @override
  String get nextOpening => 'Next opening';

  @override
  String todayStillOpen(int count) {
    return '$count still open today';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String freeFor(String duration) {
    return 'Free $duration';
  }

  @override
  String get timelineTitle => 'Today\'s timeline';

  @override
  String get scheduledLabel => 'Scheduled';

  @override
  String get freeLabel => 'Free';

  @override
  String remainingMinutes(int minutes) {
    return '$minutes min left';
  }

  @override
  String eventsAndFree(int count) {
    return '$count events';
  }

  @override
  String get nextUp => 'Next';

  @override
  String syncedAt(String time) {
    return 'Synced $time';
  }

  @override
  String get meLabel => 'Me';

  @override
  String get todayEventsHeader => 'Today\'s Events';

  @override
  String get widgetNoPlans => 'No plans for today';

  @override
  String get widgetTodos => 'Tasks';

  @override
  String get widgetAll => 'All';

  @override
  String get widgetNoTodos => 'No tasks';

  @override
  String get widgetAllTodosDone => 'Today\'s tasks are done';

  @override
  String get widgetAllPlansDone => 'Today\'s plans are done';

  @override
  String get widgetLater => 'Later';

  @override
  String get widgetDueToday => 'To do today';

  @override
  String widgetCompletedCount(int count) {
    return '$count completed';
  }

  @override
  String widgetMoreCount(int count) {
    return '$count more';
  }

  @override
  String widgetOverdueCount(int count) {
    return '$count overdue';
  }

  @override
  String get widgetSelectedDayEmpty => 'Nothing on this day';

  @override
  String get widgetCompletedCountTemplate => '%n completed';

  @override
  String get widgetMoreCountTemplate => '%n more';

  @override
  String get widgetOverdueCountTemplate => '%n overdue';

  @override
  String get widgetBackToMonth => 'Month';

  @override
  String get widgetOpenToUpdate => 'Open DaySpark to update';

  @override
  String get widgetStale => 'Data needs updating';

  @override
  String get widgetAddTodo => '+ Task';

  @override
  String get widgetAddEvent => '+ Event';

  @override
  String get widgetQuickAddHint => 'Add a task';

  @override
  String get widgetSaveFailed => 'Save failed. Please try again.';

  @override
  String get eventCreated => 'Event created';

  @override
  String get todoCreated => 'Task created';

  @override
  String get importExport => 'Import / Export';

  @override
  String get export => 'Export';

  @override
  String get fullBackup => 'DaySpark full backup';

  @override
  String get fullBackupDesc => 'Includes all data and attachment files';

  @override
  String get restore => 'Restore';

  @override
  String get backupRestored => 'Backup merged';

  @override
  String get restoreFailed => 'Merge failed';

  @override
  String get import => 'Import';

  @override
  String get advancedFeatures => 'Advanced Features';

  @override
  String get attachments => 'Attachments';

  @override
  String get calendarData => 'Import or export calendar .ics files';

  @override
  String get add => 'Add';

  @override
  String exportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String get exportFailed => 'Export failed';

  @override
  String get noCalendarToImport => 'No calendar found to import into';

  @override
  String get importFailed => 'Import failed';

  @override
  String importedResult(int events, int todos) {
    return 'Imported $events event(s) and $todos task(s)';
  }

  @override
  String importedResultWithFailed(int events, int todos, int failed) {
    return 'Imported $events event(s) and $todos task(s) ($failed failed)';
  }

  @override
  String get importExportDesc => 'Export calendar events and tasks to .ics, or import from a .ics file.';

  @override
  String get error => 'Something went wrong. Please try again.';

  @override
  String get endBeforeStart => 'End time must be after start time';

  @override
  String get aiNotConfiguredHint => 'AI not configured. Go to Settings > AI.';

  @override
  String get aiError => 'The assistant couldn\'t finish that';

  @override
  String aiFilled(String fields) {
    return 'Filled in: $fields';
  }

  @override
  String deleteEventConfirm(String title) {
    return 'Delete \"$title\"?';
  }

  @override
  String deleteRecurringEventConfirm(String title) {
    return 'Delete the whole recurring series \"$title\" and every occurrence in it?';
  }

  @override
  String get recurringSeriesNotice => 'This event repeats. Saving changes the whole series, and the times below are the series start rather than the occurrence you tapped. Editing a single occurrence is not supported yet.';

  @override
  String get allDayDragDisabled => 'All-day events cannot be moved by drag';

  @override
  String get retry => 'Retry';

  @override
  String get noTimeSlots => 'No time slot suggestions available';

  @override
  String get suggestedTimeSlots => 'Suggested Time Slots';

  @override
  String get timeSlotConflict => 'The selected time slot is now occupied or no longer available. Please select another slot.';

  @override
  String get schedulingFailed => 'Couldn\'t schedule that';

  @override
  String get noSubtaskSuggestions => 'No subtask suggestions available';

  @override
  String get taskBreakdown => 'Task Breakdown';

  @override
  String get todoCreatedShort => 'Task created';

  @override
  String get failedCreateTodo => 'Couldn\'t create the task';

  @override
  String get breakdownFailed => 'Couldn\'t break that down';

  @override
  String get eventCreatedShort => 'Event created';

  @override
  String get failedAction => 'Couldn\'t do that';

  @override
  String get noAttachments => 'No attachments';

  @override
  String get openTask => 'Not completed';

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
    return 'You have $count overdue task(s). Move due dates to today?';
  }

  @override
  String movedToToday(int count) {
    return 'Moved $count task(s) to today';
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
  String get defaultTab => 'Startup view';

  @override
  String get inbox => 'Unplanned';

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
  String get openUpdatePage => 'View release';

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
  String get modelDetectFailed => 'Couldn’t reach that provider. Check the URL and API key.';

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
  String deletedOn(String date) {
    return 'Deleted on $date';
  }

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
  String get colorRed => 'Red';

  @override
  String get colorAmber => 'Amber';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorGray => 'Gray';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorIndigo => 'Indigo';

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
  String get addTodoShort => 'Add Task';

  @override
  String get schedule => 'Schedule';

  @override
  String get breakDown => 'Break Down';

  @override
  String get eventReminder => 'Event Reminder';

  @override
  String get todoReminder => 'Task Reminder';

  @override
  String get snoozedReminder => 'Snoozed reminder';

  @override
  String get eventStartingSoon => 'Event starting soon';

  @override
  String get taskDueSoon => 'Task due soon';

  @override
  String get addAttachment => 'Add attachment';

  @override
  String get openAttachment => 'Open attachment';

  @override
  String get attachmentLocalOnly => 'Not uploaded';

  @override
  String get attachmentUnavailable => 'This attachment is not available on this device yet';

  @override
  String attachmentReady(String name) {
    return 'Attachment saved: $name';
  }

  @override
  String get attachmentFailed => 'Attachment action failed';

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
  String get notificationPermission => 'Notification permission';

  @override
  String get notificationPermissionDesc => 'Allow DaySpark to send reminder notifications';

  @override
  String get notificationPermissionAsked => 'Requested — change it in System Settings if nothing appears';

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
  String get reminders => 'Reminders';

  @override
  String get addReminder => 'Add Reminder';

  @override
  String get noReminders => 'No reminders set';

  @override
  String get reminderTriggerTime => 'Reminder Time';

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
  String get openTodoDetails => 'Open task details';

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

  @override
  String get account => 'Sync';

  @override
  String get serverUrl => 'Sync server';

  @override
  String get serverUrlInvalid => 'Please enter a valid http(s) URL';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Please enter a valid email';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Please enter a password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get logout => 'Logout';

  @override
  String get emailAlreadyRegistered => 'Email already registered';

  @override
  String get invalidCredentials => 'Invalid email or password';

  @override
  String get authFailed => 'Sign-in failed. Check the server address and try again.';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncTooltip => 'Sync';

  @override
  String get syncing => 'Syncing...';

  @override
  String get syncPulling => 'Pulling...';

  @override
  String get syncPhaseIdle => 'Idle';

  @override
  String get syncPhaseError => 'Sync error';

  @override
  String lastSync(String time) {
    return 'Last sync: $time';
  }

  @override
  String syncRejected(String codes) {
    return 'Rejected: $codes';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String hoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String get sixThings => 'Six Things';

  @override
  String get sixThingsDesc => 'Cap today\'s list at six items with a More fold';

  @override
  String moreItems(int count) {
    return 'More ($count)';
  }

  @override
  String get collapseList => 'Collapse';

  @override
  String get hideCompleted => 'Hide completed';

  @override
  String get hideCompletedDesc => 'Hide completed items from task lists';

  @override
  String get advancedSettings => 'Advanced';

  @override
  String get emptySlotSemantics => 'Empty time slot, activate to create an event';

  @override
  String get emptyCalendarHint => 'Tap an empty slot to create your first event';

  @override
  String get holidayRestBadge => 'Off';

  @override
  String get holidayWorkBadge => 'Work';

  @override
  String get termLiChun => 'Spring Begins';

  @override
  String get termYuShui => 'Rain Water';

  @override
  String get termJingZhe => 'Insects Waken';

  @override
  String get termChunFen => 'Spring Equinox';

  @override
  String get termQingMing => 'Clear and Bright';

  @override
  String get termGuYu => 'Grain Rain';

  @override
  String get termLiXia => 'Summer Begins';

  @override
  String get termXiaoMan => 'Grain Full';

  @override
  String get termMangZhong => 'Grain in Ear';

  @override
  String get termXiaZhi => 'Summer Solstice';

  @override
  String get termXiaoShu => 'Minor Heat';

  @override
  String get termDaShu => 'Major Heat';

  @override
  String get termLiQiu => 'Autumn Begins';

  @override
  String get termChuShu => 'End of Heat';

  @override
  String get termBaiLu => 'White Dew';

  @override
  String get termQiuFen => 'Autumn Equinox';

  @override
  String get termHanLu => 'Cold Dew';

  @override
  String get termShuangJiang => 'Frost Descent';

  @override
  String get termLiDong => 'Winter Begins';

  @override
  String get termXiaoXue => 'Minor Snow';

  @override
  String get termDaXue => 'Major Snow';

  @override
  String get termDongZhi => 'Winter Solstice';

  @override
  String get termXiaoHan => 'Minor Cold';

  @override
  String get termDaHan => 'Major Cold';

  @override
  String get searchEmptyTitle => 'Search your calendar';

  @override
  String get searchEmptyHint => 'Find events and tasks by title or notes.';

  @override
  String get searchSuggestions => 'From your inbox';

  @override
  String get trashEmptyHint => 'Deleted events and tasks wait here until you remove them.';

  @override
  String get trashEmptyAction => 'Back to Tasks';

  @override
  String get aichatNoKeyTitle => 'Connect an AI provider';

  @override
  String get aichatNoKeyHint => 'DaySpark uses your own API key. Add one in Settings → AI assistant, then come back.';

  @override
  String get aichatSetupKey => 'Open AI settings';

  @override
  String get tagsEmptyAction => 'Create a tag';

  @override
  String get tagEmptyHint => 'Tags group your tasks so you can filter by area.';

  @override
  String get connectedDevices => 'Connected devices';

  @override
  String get devicesEmpty => 'No devices have reported in yet.';

  @override
  String get deviceUnknownName => 'Unnamed device';

  @override
  String deviceLastSeen(String time) {
    return 'Last active $time';
  }

  @override
  String get devicesLoadFailed => 'Couldn\'t load the device list';

  @override
  String get taskAllocations => 'Scheduled time';

  @override
  String get addTaskAllocation => 'Schedule time';

  @override
  String get noTaskAllocations => 'No scheduled time';

  @override
  String get cancelTaskAllocation => 'Cancel schedule';

  @override
  String get cancelledTaskAllocation => 'Cancelled';

  @override
  String get scheduleTodo => 'Schedule Task';

  @override
  String get scheduleTodoDesc => 'Give an existing task a time here';

  @override
  String get createEventOption => 'New Event';

  @override
  String get createEventDesc => 'Add an event at this time';

  @override
  String get selectTodoToSchedule => 'Select a Task to Schedule';

  @override
  String get noSchedulableTodos => 'No pending tasks available to schedule';

  @override
  String get action => 'Today';

  @override
  String get scheduledSection => 'Scheduled';

  @override
  String get dueTodaySection => 'Due today';

  @override
  String get unplannedInbox => 'Unplanned';

  @override
  String unplannedCount(int count) {
    return '$count unplanned';
  }

  @override
  String get todayTimeline => 'Today\'s Schedule';

  @override
  String get emptyActionHint => 'No events, scheduled tasks, or deadlines for today.';

  @override
  String scheduledTodoSuccess(String summary) {
    return 'Scheduled: $summary';
  }

  @override
  String get plannedExecution => 'Planned';

  @override
  String deadlinePrefix(String date) {
    return 'Deadline: $date';
  }

  @override
  String get deadlineToday => 'Due today';

  @override
  String get eventLabel => 'Event';

  @override
  String get completedTodaySection => 'Completed Today';

  @override
  String get recurringNeedConfirmation => 'Recurring tasks need confirmation';

  @override
  String recurringNeedConfirmationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recurring tasks need confirmation',
      one: '1 recurring task needs confirmation',
    );
    return '$_temp0';
  }

  @override
  String get earlierMissed => 'Earlier missed…';

  @override
  String get earlierHistory => 'Earlier history…';

  @override
  String get todayTasks => 'Today\'s Tasks';

  @override
  String get missed => 'Missed';

  @override
  String get recurringTask => 'Recurring';

  @override
  String get actionNow => 'Now';

  @override
  String get actionDetails => 'Details';

  @override
  String get calendarDeadlineLane => 'Deadlines';

  @override
  String get calendarLegendEvent => 'Event';

  @override
  String get calendarLegendAllocation => 'Scheduled time';

  @override
  String get actionAll => 'All';

  @override
  String get edit => 'Edit';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get todoDetails => 'Task';

  @override
  String get eventDetails => 'Event';

  @override
  String get deadline => 'Deadline';

  @override
  String get deadlineTime => 'Deadline time';

  @override
  String get executionSchedule => 'Planned time';

  @override
  String get addExecution => 'Add execution time';

  @override
  String get notScheduled => 'Not scheduled';

  @override
  String get execution => 'Execution';

  @override
  String get repeatAdvanced => 'Repeat options';

  @override
  String get seriesTimeZoneShort => 'Time zone for all repeats';

  @override
  String get startsAtHint => 'Earliest day this can be done';

  @override
  String get noDeadline => 'No deadline';

  @override
  String get setDeadline => 'Set deadline';

  @override
  String get scheduleNow => 'Schedule now';

  @override
  String get actionNothingNow => 'Nothing needs you right now';

  @override
  String get actionNothingNowHint => 'Upcoming events and deadlines will show up here on the day.';

  @override
  String get actionEmptyDay => 'Nothing scheduled yet';

  @override
  String get recurringNeedsRepair => 'Some repeating tasks need a one-time fix';

  @override
  String get recurringNeedsRepairHint => 'These were imported without a time zone. Open one to confirm when it repeats.';

  @override
  String get recurringBroken => 'A repeating task cannot be calculated';

  @override
  String get recurringBrokenHint => 'Its repeat rule is no longer valid. Open it to set a new one.';

  @override
  String untilTime(String time) {
    return 'until $time';
  }

  @override
  String get laterToday => 'Next up';

  @override
  String get nothingScheduled => 'Nothing scheduled';

  @override
  String minutesShort(Object count) {
    return '$count min';
  }

  @override
  String hoursShort(Object count) {
    return '$count h';
  }

  @override
  String get repeatNever => 'Does not repeat';

  @override
  String get repeatDaily => 'Every day';

  @override
  String get repeatWeekly => 'Every week';

  @override
  String get repeatMonthly => 'Every month';

  @override
  String get repeatYearly => 'Every year';

  @override
  String get repeatCustom => 'Custom repeat…';

  @override
  String get repeatEndsNever => 'No end date';

  @override
  String repeatEndsOn(Object date) {
    return 'Ends on $date';
  }

  @override
  String repeatEndsAfter(Object count) {
    return 'Ends after $count times';
  }

  @override
  String repeatEveryN(Object count, Object unit) {
    return 'Every $count $unit';
  }

  @override
  String repeatEveryNDays(Object count) {
    return 'Every $count days';
  }

  @override
  String repeatEveryNWeeks(Object count) {
    return 'Every $count weeks';
  }

  @override
  String repeatEveryNMonths(Object count) {
    return 'Every $count months';
  }

  @override
  String repeatEveryNYears(Object count) {
    return 'Every $count years';
  }

  @override
  String get eventDuration => 'Duration';

  @override
  String get durationAllDay => 'All day';

  @override
  String get executionBlock => 'Block';

  @override
  String get executionWhen => 'When';

  @override
  String get startTime => 'Start';

  @override
  String get endTime => 'End';

  @override
  String get repeatNeedsDate => 'Give it a date first, then it can repeat.';

  @override
  String get recurringSeriesNoticeShort => 'This repeats. Edits apply to every occurrence.';

  @override
  String get actionFailedRetry => 'That didn\'t work. Please try again.';

  @override
  String get discardChanges => 'Discard changes?';

  @override
  String get discardChangesBody => 'Your edits to this item haven\'t been saved.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discard => 'Discard';

  @override
  String get clearDeadline => 'Clear deadline';

  @override
  String get cancelSchedule => 'Cancel scheduled time';

  @override
  String get removeReminder => 'Remove reminder';

  @override
  String get removeAttachment => 'Remove attachment';

  @override
  String get removeSubtask => 'Remove subtask';

  @override
  String get duration => 'Duration';

  @override
  String get lengthLabel => 'Duration';

  @override
  String get searchFailed => 'Search failed. Please try again.';

  @override
  String get scheduledTimeLower => 'Planned time';

  @override
  String get executionRow => 'Planned time';

  @override
  String get deadlineRow => 'Deadline';

  @override
  String get remindOnTime => 'On time';

  @override
  String remindMinutesBefore(int count) {
    return '$count min before';
  }

  @override
  String remindHoursBefore(int count) {
    return '$count h before';
  }

  @override
  String remindDaysBefore(int count) {
    return '$count day(s) before';
  }

  @override
  String get remindCustom => 'Custom time';

  @override
  String get reminderNeedsAnchor => 'Set a deadline or start time first, then reminders can be relative to it.';

  @override
  String get actionEarlierToday => 'Earlier today';

  @override
  String get createTodoAndSchedule => 'New & schedule';

  @override
  String calendarHasContents(int events, int todos) {
    return 'This calendar holds $events events and $todos tasks.';
  }

  @override
  String get moveContentsTo => 'Move them to';

  @override
  String get deleteCalendarAndContents => 'Delete them with the calendar';

  @override
  String get importTo => 'Import into';

  @override
  String get nothingToExport => 'Nothing to export yet';

  @override
  String get exportAllCalendars => 'Export all calendars';

  @override
  String get mergeBackup => 'Merge backup';

  @override
  String get mergeBackupDesc => 'Adds everything from the backup. Items already on this device are updated; nothing is removed.';

  @override
  String get accountLoadFailed => 'Couldn\'t load your account.';

  @override
  String get copyFeedback => 'Copy feedback';

  @override
  String get submitOnGitHub => 'Submit on GitHub';

  @override
  String get clearChatAction => 'Clear';

  @override
  String get clearChatConfirm => 'Clear this conversation? It can\'t be restored.';

  @override
  String get couldNotOpenLink => 'Couldn\'t open that link.';

  @override
  String get invalidTimeRange => 'The end has to come after the start.';

  @override
  String get deleteThisOccurrence => 'This occurrence only';

  @override
  String get deleteWholeSeries => 'The whole series';

  @override
  String get deleteScopeTitle => 'Delete which?';

  @override
  String get editOccurrenceNotice => 'You\'re editing one occurrence of a repeating event.';

  @override
  String repeatUntil(String date) {
    return 'until $date';
  }

  @override
  String repeatEveryNWeekdays(String days, int interval) {
    return 'Every $interval weeks on $days';
  }

  @override
  String repeatOnDays(String days) {
    return 'Every week on $days';
  }

  @override
  String repeatMonthlyOnDay(int day) {
    return 'Every month on day $day';
  }

  @override
  String get goneFromHere => 'This item is no longer here.';

  @override
  String get createTodoAndScheduleDesc => 'Start a task and place it in this slot';

  @override
  String get tagNameRequired => 'Tag name is required.';

  @override
  String tagNameTooLong(int count) {
    return 'Tag names can be at most $count characters.';
  }

  @override
  String tagDeleteBody(String name) {
    return 'Remove the tag \"$name\"? It will be removed from every task that uses it.';
  }

  @override
  String get tagDuplicate => 'A tag with that name already exists.';

  @override
  String get calendarNameRequired => 'Calendar name is required.';

  @override
  String get signOutConfirm => 'Log out?';

  @override
  String get signOutBody => 'Your data stays on this device. Syncing stops until you log in again.';

  @override
  String get signOut => 'Log out';

  @override
  String get newTodoAction => '+ Task';

  @override
  String get newEventAction => '+ Event';

  @override
  String get syncExplanation => 'Sync calendars and tasks across your devices through your self-hosted DaySpark Sync Server.';

  @override
  String get calendarField => 'Calendar';

  @override
  String get calendarExplanation => 'Calendars group and color events and tasks. To place a task on the timeline, use Planned time.';

  @override
  String get sectionTask => 'Task';

  @override
  String get sectionTime => 'Time';

  @override
  String get sectionReminder => 'Reminders';

  @override
  String get sectionOrganize => 'Organize';

  @override
  String get sectionContent => 'Content';

  @override
  String get dataExchange => 'Calendar data exchange';

  @override
  String get daysparkBackup => 'DaySpark backup';

  @override
  String get importIcs => 'Import .ics';

  @override
  String get exportIcs => 'Export .ics';

  @override
  String get displayOptions => 'Display';

  @override
  String get aiConfigured => 'Configured';

  @override
  String get aiNotConfiguredShort => 'Not configured';

  @override
  String get defaultCalendarName => 'Personal';

  @override
  String get quickAddTodo => 'Add task';

  @override
  String get quickCreateHint => 'Task title';

  @override
  String get moreOptions => 'More';

  @override
  String get lessOptions => 'Less';

  @override
  String get addTime => 'Add time';

  @override
  String get remindNone => 'No reminder';

  @override
  String get notes => 'Notes';

  @override
  String get notesHint => 'Add notes';

  @override
  String get openFullForm => 'Open full form';

  @override
  String get moreSection => 'More';

  @override
  String get inProgress => 'In progress';

  @override
  String get executingPlan => 'Executing';

  @override
  String get createCalendarFromPicker => '+ New calendar';

  @override
  String get byDate => 'By date';

  @override
  String get showCompleted => 'Show completed';

  @override
  String get filterAndDisplay => 'Filter & display';

  @override
  String get clearFilters => 'Clear';

  @override
  String get allLabel => 'All';

  @override
  String get unplannedViewEmptyTitle => 'No unplanned tasks';

  @override
  String get unplannedViewEmptyHint => 'Every task has a planned time. Switch to All Tasks to see everything.';

  @override
  String get todosSwitchMode => 'Switch view';

  @override
  String get todosEmptyTitle => 'No tasks here';

  @override
  String get todosEmptyHint => 'Write down what you need to do, no need to decide when yet.';

  @override
  String get noPlannedExecution => 'Not scheduled';

  @override
  String get unplannedRailHint => 'Tasks without a planned time. Schedule one to give it a place in the day.';

  @override
  String get unplannedRailEmpty => 'Everything is scheduled.';

  @override
  String get allScheduled => 'everything scheduled';

  @override
  String get selectTodoPaneTitle => 'Select a task';

  @override
  String get selectTodoPaneHint => 'Choose a task on the left, or add one above.';

  @override
  String filterCountLabel(int count) {
    return '$count filters';
  }

  @override
  String todoAllContext(int count) {
    return '$count unfinished';
  }

  @override
  String get calendarTags => 'Calendar & tags';

  @override
  String get other => 'Other';

  @override
  String get capturePlaceholder => 'Capture · Enter files it unplanned';

  @override
  String get captureHintEnter => '⏎ Unplanned';

  @override
  String get captureHintSubmit => 'Add';

  @override
  String get captureAddedToast => 'Added to Unplanned · keep typing';

  @override
  String get justAddedLabel => 'Just added';

  @override
  String groupCountItems(int count) {
    return '$count items';
  }

  @override
  String expandRemaining(int count) {
    return '$count more · Show all';
  }

  @override
  String get collapseLabel => 'Show less';

  @override
  String get sectionNow => 'Now';

  @override
  String get sectionUpcoming => 'Upcoming';

  @override
  String get sectionDueToday => 'Due today';

  @override
  String get sectionOverdueLabel => 'Overdue';

  @override
  String get scheduleAction => 'Schedule';

  @override
  String get noExecutionSlot => 'No execution slot';

  @override
  String plannedRangeLabel(String range) {
    return 'Planned $range';
  }

  @override
  String plannedShortRangeLabel(String range) {
    return 'Plan $range';
  }

  @override
  String dueValueLabel(String value) {
    return 'Due $value';
  }

  @override
  String dueTodayTimeLabel(String time) {
    return 'Due today $time';
  }

  @override
  String get allDayLabel => 'All day';

  @override
  String get emptyTodayTitle => 'Nothing scheduled today';

  @override
  String get emptyTodayHint => 'Write it down anytime — Enter files it under Unplanned';

  @override
  String get emptyUnplannedTitle => 'Unplanned is empty';

  @override
  String get emptyUnplannedHint => 'Capture one — Enter puts it here';

  @override
  String get emptyDateTitle => 'Nothing on this day';

  @override
  String get emptyDateHint => 'Add one with “Plan this day” below';

  @override
  String get allDueTodaySection => 'Due today';

  @override
  String get allPastDueSection => 'Past due';

  @override
  String get allLaterSection => 'Later';

  @override
  String get allUnplannedNoDueSection => 'No deadline';

  @override
  String get withDueUnplannedSection => 'With a deadline · unplanned';

  @override
  String get noDueSection => 'No deadline';

  @override
  String get datePlannedSection => 'Planned';

  @override
  String get dateDueSection => 'Deadline';

  @override
  String get dateEventsSection => 'Events';

  @override
  String todoUnplannedContext(int count, int withDue) {
    return '$count items · $withDue with a deadline';
  }

  @override
  String todoAllSummary(int count, int active) {
    return '$count items · $active active';
  }

  @override
  String get byDateTitle => 'By date';

  @override
  String get byDateContext => 'Todos · shares its date with Calendar';

  @override
  String get planThisDay => 'Plan this day';

  @override
  String planToDate(String date) {
    return 'Plan to $date';
  }

  @override
  String inDaysCount(int count) {
    return 'In $count days';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String yearMonthTitle(String year, String month) {
    return '$year / $month';
  }

  @override
  String get yearLabel => 'Year';

  @override
  String get composerPlaceholder => 'What needs doing?';

  @override
  String get saveToUnplanned => 'Save to Unplanned';

  @override
  String savePlannedTo(String date) {
    return 'Plan for $date';
  }

  @override
  String saveWithDueDate(String date) {
    return 'Save (due $date)';
  }

  @override
  String get composerHintNoSlot => 'Saving without a slot files this under Unplanned.';

  @override
  String get composerHintAlloc => 'This is a planned execution, not a deadline. Set the deadline separately.';

  @override
  String get composerHintDue => 'A deadline is the latest finish; a planned execution is when you chose to do it.';

  @override
  String get composerNoSlot => 'No slot chosen';

  @override
  String get composerUnset => 'Not set';

  @override
  String get composerCustomSlot => 'Custom…';

  @override
  String get moreActions => 'More';

  @override
  String weekNumberLabel(int week) {
    return 'Week $week';
  }

  @override
  String get daySegmentLabel => 'Day';

  @override
  String get captureQuickAddLabel => 'Capture';

  @override
  String get calendarTodayHint => 'Go to today';

  @override
  String get unplannedGroupEmpty => 'Nothing unplanned';

  @override
  String get pickDateHint => 'Pick a date';

  @override
  String get moreItemsHint => 'More';

  @override
  String get startPlanning => 'Plan it';

  @override
  String eventCountLabel(int count) {
    return '$count';
  }

  @override
  String get composerOptional => 'Optional';

  @override
  String get previousDay => 'Previous day';

  @override
  String get nextDay => 'Next day';

  @override
  String undoOccurrence(String label) {
    return 'Undo · $label';
  }

  @override
  String get backToNow => 'Back to now';

  @override
  String dawnQuiet(String start, String end) {
    return '$start–$end · quiet hours, nothing scheduled';
  }

  @override
  String get slotRangeExistingEvent => 'Existing event';

  @override
  String get slotRangeDefaultEditable => 'default, editable';

  @override
  String get slotEmptyCreateHint => 'Nothing to schedule yet — create one and it lands in this slot.';

  @override
  String get navMe => 'Me';

  @override
  String get todayCleanTitle => 'Today is clear';

  @override
  String get todayCleanSub => 'Capture a task below, it will land in Unplanned.';

  @override
  String get todayEmptyTime => 'No time scheduled today.';

  @override
  String get todayEmptyTimeWithHint => 'No time scheduled today. You can schedule tasks onto time slots from Calendar.';

  @override
  String get captureInputPlaceholder => 'Capture a task, press Enter';

  @override
  String get captureTypeTodo => 'Task';

  @override
  String get captureDefaultDate => 'No date · Personal';

  @override
  String deleteConfirmTitle(String title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get deleteConfirmBody => 'Will be moved to Trash.';

  @override
  String todaySummary(int overdue, int due, int unplanned, int done) {
    return '$overdue overdue · $due due today · $unplanned no date · $done completed';
  }

  @override
  String get todaySummaryEmpty => 'No tasks scheduled today';

  @override
  String get todayCompletedGroup => 'Completed Today';

  @override
  String get todayEarlyGroup => 'Earlier Today';

  @override
  String get todayNowGroup => 'Now';

  @override
  String get todayUpcomingGroup => 'Next Up';

  @override
  String get todayOverdueGroup => 'Overdue';

  @override
  String get todayDueGroup => 'Due Today';

  @override
  String get todayUnplannedGroup => 'No Date';

  @override
  String expandTodayDone(int count) {
    return 'Completed today $count · Expand';
  }

  @override
  String expandTodayEarly(int count) {
    return 'Earlier today $count · Expand';
  }

  @override
  String collapseTodayEarly(int count) {
    return 'Earlier today $count · Collapse';
  }

  @override
  String viewAllNItems(int count) {
    return 'View all $count items';
  }

  @override
  String plannedBitsNote(String items) {
    return '$items more items shown in the time section.';
  }

  @override
  String plannedBitsOverdue(int count) {
    return '$count overdue / missed';
  }

  @override
  String plannedBitsDue(int count) {
    return '$count due today';
  }

  @override
  String get sortDeadline => 'Sort by deadline';

  @override
  String nItemsOverdue(int count) {
    return '$count overdue';
  }

  @override
  String markedCompleted(String title) {
    return 'Marked completed · $title';
  }

  @override
  String get tasksZoneLabel => 'TASKS';

  @override
  String get timeZoneLabel => 'TIME';

  @override
  String get captureDefaultSub => 'No date · Personal';

  @override
  String get planTagLabel => 'Plan';

  @override
  String todayDateSubtitle(String date, String weekday) {
    return '$date · $weekday';
  }

  @override
  String get showCalendars => 'Display Calendars';

  @override
  String get restoreAllCalendars => 'Restore All';

  @override
  String hiddenCalendarsSummary(int count) {
    return 'Hidden $count calendars';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get hiddenBadge => 'Hidden';

  @override
  String get repeatEndLabel => 'Ends';

  @override
  String get repeatNeverEnd => 'Never';

  @override
  String get repeatOnDate => 'On date';

  @override
  String get repeatAfterCount => 'After count';

  @override
  String get repeatEndDate => 'End date';

  @override
  String get repeatCount => 'Occurrences';

  @override
  String get repeatSeriesNotice => 'Updating frequency or end applies to the entire series.';

  @override
  String planTodoModalTitle(String title) {
    return 'Schedule \"$title\"';
  }

  @override
  String get planTodoSub => 'Sets planned execution only; does not change deadline.';

  @override
  String get planEditSub => 'Editing time; sets planned execution only.';

  @override
  String get planDate => 'Plan Date';

  @override
  String get planStartTime => 'Start';

  @override
  String get planEndTime => 'End';

  @override
  String get planDuration => 'Duration';

  @override
  String get planSubmitAction => 'Schedule';

  @override
  String get planSaveTimeAction => 'Save Time';

  @override
  String get planNoConflict => 'No time conflict';

  @override
  String planConflictWith(String title) {
    return 'Overlaps with $title';
  }

  @override
  String planDurationMinutes(int count) {
    return '$count min';
  }

  @override
  String planDurationHours(int hours) {
    return '$hours hr';
  }

  @override
  String planDurationHoursMinutes(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String get detailEmptyTitle => 'No Task Selected';

  @override
  String get detailEmptyHint => 'Select a task from the list to view its details.';

  @override
  String get completeThisOccurrence => 'Complete This Occurrence';

  @override
  String get completedThisOccurrence => 'This Occurrence Completed';

  @override
  String missedOccurrencesNote(String date, int count) {
    return 'Current instance $date · Missed $count times';
  }

  @override
  String get deleteToTrashAction => 'Move to Trash';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get saveAction => 'Save';

  @override
  String get titleRequired => 'Title cannot be empty.';

  @override
  String get endTimeAfterStartTime => 'End time must be after start time.';

  @override
  String timeArrangementsCount(int count) {
    return '$count scheduled items';
  }

  @override
  String dayAgendaContextNotice(int count) {
    return 'Day\'s events $count items · Time context only';
  }

  @override
  String moreUnplannedItems(int count) {
    return 'View $count undated items';
  }

  @override
  String get defaultCalendar => 'Default Calendar';

  @override
  String get defaultCalendarDesc => 'Only decides where new items land by default; does not change existing items.';

  @override
  String get defaultCalendarSettingDesc => 'New tasks and captures land here by default; uses the first calendar if unset, no \"Uncategorized\".';

  @override
  String get defaultCalendarAlert => 'No \"Uncategorized\": if unset, the first calendar in the list is used.';

  @override
  String get saveDefaultCalendar => 'Save Default Calendar';

  @override
  String get defaultCalendarSaved => 'Default calendar saved';

  @override
  String get badgeDefault => 'Default';

  @override
  String get settingsSubtitle => 'Default calendar, data and preferences';

  @override
  String get settingsHomeDesc => 'Set the default calendar first, then manage data and sync.';

  @override
  String get general => 'General';

  @override
  String get generalDesc => 'Decide where new tasks land and what to see on startup.';

  @override
  String get themeDesc => 'Warm paper surface, white content; ink for selection and actions.';

  @override
  String get accentColorDesc => 'Only affects actions and selection, not calendar colors.';

  @override
  String get accentWarmGray => 'Warm Gray';

  @override
  String get startupViewDesc => 'Which primary view to open on cold start.';

  @override
  String get languageDesc => 'Interface language.';

  @override
  String get calendarManagementDesc => 'Calendars are shared grouping and color spaces for events and tasks.';

  @override
  String get deleteCalendarNotice => 'When deleting a calendar, you must choose: migrate contents to another calendar, or delete them together.';

  @override
  String get newCalendarDesc => 'Choose name and color; new calendars do not become default automatically, select in \"Default Calendar\" after creation.';

  @override
  String editCalendarDesc(String name) {
    return 'Editing \"$name\"; name, color. Change default calendar in separate setting.';
  }

  @override
  String deleteCalendarHeader(String name, int count) {
    return 'Before deleting \"$name\", you must decide where $count items go.';
  }

  @override
  String get deleteCalendarWarning => 'Will not silently delete contents. Events and tasks must be migrated, or deleted together with the calendar.';

  @override
  String get migrateTo => 'Migrate to';

  @override
  String migrateItemCount(String name, int count) {
    return '$name · migrate $count items';
  }

  @override
  String deleteWithContents(int count) {
    return 'Delete together with $count items (move to trash)';
  }

  @override
  String get confirmMigrateAndDelete => 'Confirm Migration and Delete';

  @override
  String get calendarPlaceholder => 'e.g. Side project';

  @override
  String get tagPlaceholder => 'e.g. Waiting for reply';

  @override
  String get tagManagementDesc => 'Tags are not calendars; they are used for cross-calendar filtering.';

  @override
  String tagEditDesc(String name) {
    return 'Editing \"$name\"; tags are cross-calendar, renaming does not alter items.';
  }

  @override
  String get tagDeleteBanner => 'Deleting a tag only removes the tag, not the items.';

  @override
  String get trashDesc => 'Deleted tasks and events land here; restoring returns them to their original calendar.';

  @override
  String trashRestoredBanner(String title) {
    return 'Restored \"$title\", returned to its original calendar.';
  }

  @override
  String trashPermanentDeleteConfirm(String title) {
    return 'Permanently delete \"$title\"? Cannot be undone, will not sync to other devices.';
  }

  @override
  String trashDeletedBanner(String title) {
    return 'Permanently deleted \"$title\", no longer kept in trash.';
  }

  @override
  String get trashClearedBanner => 'Trash cleared, no items to restore.';

  @override
  String get ioSectionDesc => 'ICS is for exchanging with other calendars; backup is for restoring DaySpark.';

  @override
  String get ioCardImportDesc => 'Select target calendar; events and dated tasks are imported from ICS fields.';

  @override
  String get ioCardExportDesc => 'Export all calendars; none silently omitted.';

  @override
  String get ioCardBackupDesc => 'Contains all calendars, tasks, events, tags, reminders and attachment index.';

  @override
  String get notifySectionDesc => 'Reminders belong to each item; this manages system permissions only.';

  @override
  String get notifyDeniedBanner => 'System notification permission is off. Reminders are saved, but will not alert when due.';

  @override
  String get openSystemSettings => 'Open System Settings';

  @override
  String get inAppReminders => 'In-app Reminders';

  @override
  String get inAppRemindersDesc => 'Displays in foreground';

  @override
  String get available => 'Available';

  @override
  String get syncSectionDesc => 'DaySpark self-hosted multi-device sync.';

  @override
  String get syncLoggedOutBanner => 'Not logged in yet. Local still works; login for multi-device sync.';

  @override
  String get syncFailedBanner => 'Sync failed. Server timed out; local changes pending retry.';

  @override
  String get retryNow => 'Retry Now';

  @override
  String get localStatus => 'Local Status';

  @override
  String get localPriority => 'Local Priority';

  @override
  String get keepLocal => 'Keep Local';

  @override
  String get keepServer => 'Keep Server';

  @override
  String get mergeConflict => 'Merge';

  @override
  String get acceptDeletion => 'Accept Deletion';

  @override
  String get aboutDesc => 'DaySpark · Local-first personal time management tool.';

  @override
  String get dataLocation => 'Data';

  @override
  String get dataLocationDesc => 'Local-first · Self-hosted sync';

  @override
  String get license => 'License';

  @override
  String get viewLicense => 'View';

  @override
  String get commandPlaceholder => 'Search tasks, events, or type an action';

  @override
  String get commandHintRecent => 'Recent';

  @override
  String get commandHintActions => 'Actions';

  @override
  String get commandHintTodos => 'Tasks';

  @override
  String get commandHintEvents => 'Events';

  @override
  String get commandCreateTodo => 'New Task';

  @override
  String get commandCreateEvent => 'New Event';

  @override
  String get commandGoSettings => 'Go to Settings';

  @override
  String get commandGoSettingsDesc => 'Default calendar, data and preferences';

  @override
  String commandNotFound(String query) {
    return 'No results found for \"$query\"';
  }

  @override
  String get commandFootSelect => '↑↓ Navigate';

  @override
  String get commandFootOpen => '↵ Open';

  @override
  String get commandFootClose => 'esc Close';

  @override
  String get commandFootHint => 'Content first, actions after';

  @override
  String get currentCalendarIsDefault => 'This calendar is default';

  @override
  String get currentDefaultPrefix => 'Current default: ';

  @override
  String get goToSettings => 'Configure';

  @override
  String get orAlternative => 'Or';

  @override
  String get calendarColorLabel => 'Color';

  @override
  String get noSchedule => 'No schedule';

  @override
  String deadlineMarkerLabel(String time, String title) {
    return 'Due $time · $title';
  }

  @override
  String calendarTimeRowPlanned(String timeRange) {
    return '$timeRange · Planned';
  }
}
