import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'DaySpark'**
  String get appName;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @todos.
  ///
  /// In en, this message translates to:
  /// **'Todos'**
  String get todos;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @newEvent.
  ///
  /// In en, this message translates to:
  /// **'New Event'**
  String get newEvent;

  /// No description provided for @newTodo.
  ///
  /// In en, this message translates to:
  /// **'New Todo'**
  String get newTodo;

  /// No description provided for @editEvent.
  ///
  /// In en, this message translates to:
  /// **'Edit Event'**
  String get editEvent;

  /// No description provided for @editTodo.
  ///
  /// In en, this message translates to:
  /// **'Edit Todo'**
  String get editTodo;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Starts at'**
  String get startDate;

  /// No description provided for @endDate.
  ///
  /// In en, this message translates to:
  /// **'Ends at'**
  String get endDate;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDate;

  /// No description provided for @allDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get allDay;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @priorityNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get priorityNone;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get priorityLow;

  /// No description provided for @priorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get priorityMedium;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get priorityHigh;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @manageTags.
  ///
  /// In en, this message translates to:
  /// **'Manage Tags'**
  String get manageTags;

  /// No description provided for @createTag.
  ///
  /// In en, this message translates to:
  /// **'Create Tag'**
  String get createTag;

  /// No description provided for @deleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete Tag'**
  String get deleteTag;

  /// No description provided for @tagName.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get tagName;

  /// No description provided for @noTags.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get noTags;

  /// No description provided for @caldavAccount.
  ///
  /// In en, this message translates to:
  /// **'CalDAV Account'**
  String get caldavAccount;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove Account'**
  String get removeAccount;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @lastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String lastSync(String time);

  /// No description provided for @notConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get notConfigured;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected as {user}'**
  String connected(String user);

  /// No description provided for @aiConfig.
  ///
  /// In en, this message translates to:
  /// **'AI Configuration'**
  String get aiConfig;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @aiHint.
  ///
  /// In en, this message translates to:
  /// **'Ask me to create events or todos'**
  String get aiHint;

  /// No description provided for @aiExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. \"Meeting with John tomorrow 3pm\"'**
  String get aiExample;

  /// No description provided for @aiNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI is not configured'**
  String get aiNotConfigured;

  /// No description provided for @aiGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings > AI to configure your API key'**
  String get aiGoToSettings;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @noPendingTodos.
  ///
  /// In en, this message translates to:
  /// **'No pending todos'**
  String get noPendingTodos;

  /// No description provided for @tapToCreate.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create one'**
  String get tapToCreate;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @enterTitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title'**
  String get enterTitle;

  /// No description provided for @noCalendar.
  ///
  /// In en, this message translates to:
  /// **'No calendar available. Add one in Settings.'**
  String get noCalendar;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete?'**
  String get confirmDelete;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessage;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get day;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// No description provided for @typeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search'**
  String get typeToSearch;

  /// No description provided for @eventCreated.
  ///
  /// In en, this message translates to:
  /// **'Event created'**
  String get eventCreated;

  /// No description provided for @todoCreated.
  ///
  /// In en, this message translates to:
  /// **'Todo created'**
  String get todoCreated;

  /// No description provided for @importExport.
  ///
  /// In en, this message translates to:
  /// **'Import / Export'**
  String get importExport;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @defaultReminderTimes.
  ///
  /// In en, this message translates to:
  /// **'Default reminder times'**
  String get defaultReminderTimes;

  /// No description provided for @advancedFeatures.
  ///
  /// In en, this message translates to:
  /// **'Advanced Features'**
  String get advancedFeatures;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @calendarData.
  ///
  /// In en, this message translates to:
  /// **'Calendar data'**
  String get calendarData;

  /// No description provided for @caldavAccounts.
  ///
  /// In en, this message translates to:
  /// **'CalDAV Accounts'**
  String get caldavAccounts;

  /// No description provided for @noAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts configured yet.'**
  String get noAccounts;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add CalDAV Account'**
  String get addAccount;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Account Name'**
  String get accountName;

  /// No description provided for @accountNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Work, Personal'**
  String get accountNameHint;

  /// No description provided for @removeAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" and all its calendars?'**
  String removeAccountConfirm(String name);

  /// No description provided for @removeAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Account'**
  String get removeAccountTitle;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(String error);

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportedTo(String path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @noCalendarToImport.
  ///
  /// In en, this message translates to:
  /// **'No calendar found to import into'**
  String get noCalendarToImport;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @importedResult.
  ///
  /// In en, this message translates to:
  /// **'Imported {events} event(s) and {todos} todo(s)'**
  String importedResult(int events, int todos);

  /// No description provided for @importExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Export calendar events and todos to .ics, or import from a .ics file.'**
  String get importExportDesc;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error(String error);

  /// No description provided for @endBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End time must be after start time'**
  String get endBeforeStart;

  /// No description provided for @aiNotConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'AI not configured. Go to Settings > AI.'**
  String get aiNotConfiguredHint;

  /// No description provided for @aiError.
  ///
  /// In en, this message translates to:
  /// **'AI error: {error}'**
  String aiError(String error);

  /// No description provided for @deleteEventConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String deleteEventConfirm(String title);

  /// No description provided for @noTimeSlots.
  ///
  /// In en, this message translates to:
  /// **'No time slot suggestions available'**
  String get noTimeSlots;

  /// No description provided for @suggestedTimeSlots.
  ///
  /// In en, this message translates to:
  /// **'Suggested Time Slots'**
  String get suggestedTimeSlots;

  /// No description provided for @schedulingFailed.
  ///
  /// In en, this message translates to:
  /// **'Scheduling failed: {error}'**
  String schedulingFailed(String error);

  /// No description provided for @noSubtasks.
  ///
  /// In en, this message translates to:
  /// **'No subtask suggestions available'**
  String get noSubtasks;

  /// No description provided for @taskBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Task Breakdown'**
  String get taskBreakdown;

  /// No description provided for @todoCreatedShort.
  ///
  /// In en, this message translates to:
  /// **'Todo created'**
  String get todoCreatedShort;

  /// No description provided for @failedCreateTodo.
  ///
  /// In en, this message translates to:
  /// **'Failed to create todo: {error}'**
  String failedCreateTodo(String error);

  /// No description provided for @breakdownFailed.
  ///
  /// In en, this message translates to:
  /// **'Breakdown failed: {error}'**
  String breakdownFailed(String error);

  /// No description provided for @eventCreatedShort.
  ///
  /// In en, this message translates to:
  /// **'Event created'**
  String get eventCreatedShort;

  /// No description provided for @failedAction.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failedAction(String error);

  /// No description provided for @noAttachments.
  ///
  /// In en, this message translates to:
  /// **'No attachments'**
  String get noAttachments;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @dayAfterTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Day after'**
  String get dayAfterTomorrow;

  /// No description provided for @nextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get nextWeek;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @allTasks.
  ///
  /// In en, this message translates to:
  /// **'All Tasks'**
  String get allTasks;

  /// No description provided for @noDueDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get noDueDate;

  /// No description provided for @moveToToday.
  ///
  /// In en, this message translates to:
  /// **'Move to today'**
  String get moveToToday;

  /// No description provided for @moveToTodayPrompt.
  ///
  /// In en, this message translates to:
  /// **'You have {count} overdue todo(s). Move due dates to today?'**
  String moveToTodayPrompt(Object count);

  /// No description provided for @movedToToday.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} todo(s) to today'**
  String movedToToday(Object count);

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @pendingTodos.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingTodos;

  /// No description provided for @goToToday.
  ///
  /// In en, this message translates to:
  /// **'Return to Today'**
  String get goToToday;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @defaultTab.
  ///
  /// In en, this message translates to:
  /// **'Tab Order'**
  String get defaultTab;

  /// No description provided for @defaultTabDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose the order of calendar and todos tabs'**
  String get defaultTabDesc;

  /// No description provided for @calendarFirst.
  ///
  /// In en, this message translates to:
  /// **'Calendar First'**
  String get calendarFirst;

  /// No description provided for @todosFirst.
  ///
  /// In en, this message translates to:
  /// **'Todos First'**
  String get todosFirst;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'To-do Box'**
  String get inbox;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get emptyTrash;

  /// No description provided for @restoreTodo.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreTodo;

  /// No description provided for @permanentDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get permanentDelete;

  /// No description provided for @trashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashEmpty;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @confirmPermanentDelete.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete? This cannot be undone.'**
  String get confirmPermanentDelete;

  /// No description provided for @confirmEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all items in trash?'**
  String get confirmEmptyTrash;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @noDate.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get noDate;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String dateLabel(int month, int day);

  /// No description provided for @checkUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkUpdate;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get upToDate;

  /// No description provided for @newVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version available: {version}'**
  String newVersionAvailable(String version);

  /// No description provided for @currentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get currentVersion;

  /// No description provided for @downloadUpdate.
  ///
  /// In en, this message translates to:
  /// **'Download Update'**
  String get downloadUpdate;

  /// No description provided for @starOnGithub.
  ///
  /// In en, this message translates to:
  /// **'Star on GitHub'**
  String get starOnGithub;

  /// No description provided for @reportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get reportIssue;

  /// No description provided for @setupGuide.
  ///
  /// In en, this message translates to:
  /// **'Setup Guide'**
  String get setupGuide;

  /// No description provided for @aiProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiProvider;

  /// No description provided for @customProvider.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customProvider;

  /// No description provided for @detectModels.
  ///
  /// In en, this message translates to:
  /// **'Detect Models'**
  String get detectModels;

  /// No description provided for @detectingModels.
  ///
  /// In en, this message translates to:
  /// **'Detecting...'**
  String get detectingModels;

  /// No description provided for @noModelsFound.
  ///
  /// In en, this message translates to:
  /// **'No models found'**
  String get noModelsFound;

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get selectModel;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @tutorial.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get tutorial;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @snoozedFor.
  ///
  /// In en, this message translates to:
  /// **'Snoozed for {duration}'**
  String snoozedFor(String duration);

  /// No description provided for @markComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark Complete'**
  String get markComplete;

  /// No description provided for @snooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get snooze;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @resetColor.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetColor;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your feedback or bug report...'**
  String get feedbackHint;

  /// No description provided for @feedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Feedback'**
  String get feedbackSubmit;

  /// No description provided for @feedbackCopied.
  ///
  /// In en, this message translates to:
  /// **'Feedback copied to clipboard'**
  String get feedbackCopied;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s New'**
  String get whatsNew;

  /// No description provided for @changelogDismiss.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get changelogDismiss;

  /// No description provided for @addEventShort.
  ///
  /// In en, this message translates to:
  /// **'Add Event'**
  String get addEventShort;

  /// No description provided for @addTodoShort.
  ///
  /// In en, this message translates to:
  /// **'Add Todo'**
  String get addTodoShort;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @breakDown.
  ///
  /// In en, this message translates to:
  /// **'Break Down'**
  String get breakDown;

  /// No description provided for @eventReminder.
  ///
  /// In en, this message translates to:
  /// **'Event Reminder'**
  String get eventReminder;

  /// No description provided for @todoReminder.
  ///
  /// In en, this message translates to:
  /// **'Todo Reminder'**
  String get todoReminder;

  /// No description provided for @snoozedReminder.
  ///
  /// In en, this message translates to:
  /// **'Snoozed reminder'**
  String get snoozedReminder;

  /// No description provided for @eventStartingSoon.
  ///
  /// In en, this message translates to:
  /// **'Event starting soon'**
  String get eventStartingSoon;

  /// No description provided for @taskDueSoon.
  ///
  /// In en, this message translates to:
  /// **'Task due soon'**
  String get taskDueSoon;

  /// No description provided for @addAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get addAttachment;

  /// No description provided for @defaultAccountName.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultAccountName;

  /// No description provided for @mcpServer.
  ///
  /// In en, this message translates to:
  /// **'MCP Server'**
  String get mcpServer;

  /// No description provided for @mcpServerRunning.
  ///
  /// In en, this message translates to:
  /// **'Running on port {port}'**
  String mcpServerRunning(int port);

  /// No description provided for @mcpServerStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get mcpServerStopped;

  /// No description provided for @mcpPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get mcpPort;

  /// No description provided for @editTag.
  ///
  /// In en, this message translates to:
  /// **'Edit Tag'**
  String get editTag;

  /// No description provided for @thirdPartyLicenses.
  ///
  /// In en, this message translates to:
  /// **'Third-Party Licenses'**
  String get thirdPartyLicenses;

  /// No description provided for @databaseExport.
  ///
  /// In en, this message translates to:
  /// **'Export Database'**
  String get databaseExport;

  /// No description provided for @databaseImport.
  ///
  /// In en, this message translates to:
  /// **'Import Database'**
  String get databaseImport;

  /// No description provided for @databaseImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will replace all current data. Continue?'**
  String get databaseImportConfirm;

  /// No description provided for @databaseImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Database imported. Please restart the app.'**
  String get databaseImportSuccess;

  /// No description provided for @databaseExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Database export failed: {error}'**
  String databaseExportFailed(String error);

  /// No description provided for @databaseImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Database import failed: {error}'**
  String databaseImportFailed(String error);

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @biometricLock.
  ///
  /// In en, this message translates to:
  /// **'Biometric Lock'**
  String get biometricLock;

  /// No description provided for @biometricLockDesc.
  ///
  /// In en, this message translates to:
  /// **'Require biometric authentication to open the app'**
  String get biometricLockDesc;

  /// No description provided for @biometricPrompt.
  ///
  /// In en, this message translates to:
  /// **'Unlock DaySpark'**
  String get biometricPrompt;

  /// No description provided for @backgroundSync.
  ///
  /// In en, this message translates to:
  /// **'Background Sync'**
  String get backgroundSync;

  /// No description provided for @backgroundSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Periodically sync calendars in the background'**
  String get backgroundSyncDesc;

  /// No description provided for @recurringDragDisabled.
  ///
  /// In en, this message translates to:
  /// **'Recurring events cannot be moved by drag'**
  String get recurringDragDisabled;

  /// No description provided for @eventMoved.
  ///
  /// In en, this message translates to:
  /// **'Event moved'**
  String get eventMoved;

  /// No description provided for @systemAlarm.
  ///
  /// In en, this message translates to:
  /// **'System Alarm'**
  String get systemAlarm;

  /// No description provided for @systemAlarmDesc.
  ///
  /// In en, this message translates to:
  /// **'Play alarm sound for reminders'**
  String get systemAlarmDesc;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
