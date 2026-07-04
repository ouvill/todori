import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Todori'**
  String get appTitle;

  /// No description provided for @listsTitle.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get listsTitle;

  /// No description provided for @listsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get listsSectionTitle;

  /// No description provided for @listsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No lists yet. Tap + to create one.'**
  String get listsEmpty;

  /// No description provided for @listsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No lists yet.'**
  String get listsEmptyTitle;

  /// No description provided for @listsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create one.'**
  String get listsEmptyBody;

  /// No description provided for @failedToLoadLists.
  ///
  /// In en, this message translates to:
  /// **'Failed to load lists: {error}'**
  String failedToLoadLists(String error);

  /// No description provided for @newListTooltip.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get newListTooltip;

  /// No description provided for @newListTitle.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get newListTitle;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @createButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createButton;

  /// No description provided for @tasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTitle;

  /// No description provided for @todayTitle.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayTitle;

  /// No description provided for @homeTasksSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get homeTasksSectionTitle;

  /// No description provided for @homePendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String homePendingCount(int count);

  /// No description provided for @homeListMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open lists'**
  String get homeListMenuTooltip;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Start with a list.'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Create a list, then Todori will open straight into your tasks.'**
  String get homeEmptyBody;

  /// No description provided for @homeNewListButton.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get homeNewListButton;

  /// No description provided for @addTaskButton.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTaskButton;

  /// No description provided for @tasksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet. Tap + to create one.'**
  String get tasksEmpty;

  /// No description provided for @tasksEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet.'**
  String get tasksEmptyTitle;

  /// No description provided for @tasksEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create one.'**
  String get tasksEmptyBody;

  /// No description provided for @failedToLoadTasks.
  ///
  /// In en, this message translates to:
  /// **'Failed to load tasks: {error}'**
  String failedToLoadTasks(String error);

  /// No description provided for @newTaskTooltip.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTaskTooltip;

  /// No description provided for @newTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTaskTitle;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @noteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteLabel;

  /// No description provided for @taskDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Task detail'**
  String get taskDetailTitle;

  /// No description provided for @failedToLoadTask.
  ///
  /// In en, this message translates to:
  /// **'Failed to load task: {error}'**
  String failedToLoadTask(String error);

  /// No description provided for @taskNotFound.
  ///
  /// In en, this message translates to:
  /// **'Task not found.'**
  String get taskNotFound;

  /// No description provided for @taskPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority: {priority}'**
  String taskPriority(String priority);

  /// No description provided for @taskDueAt.
  ///
  /// In en, this message translates to:
  /// **'{dueAt}'**
  String taskDueAt(String dueAt);

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dueToday;

  /// No description provided for @dueTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dueTomorrow;

  /// No description provided for @taskDueOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue: {dueAt}'**
  String taskDueOverdue(String dueAt);

  /// No description provided for @taskCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created at: {createdAt}'**
  String taskCreatedAt(String createdAt);

  /// No description provided for @subtasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get subtasksTitle;

  /// No description provided for @subtasksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No subtasks yet.'**
  String get subtasksEmpty;

  /// No description provided for @addSubtaskButton.
  ///
  /// In en, this message translates to:
  /// **'Add subtask'**
  String get addSubtaskButton;

  /// No description provided for @newSubtaskTitle.
  ///
  /// In en, this message translates to:
  /// **'New subtask'**
  String get newSubtaskTitle;

  /// No description provided for @subtaskProgress.
  ///
  /// In en, this message translates to:
  /// **'{doneCount}/{totalCount}'**
  String subtaskProgress(int doneCount, int totalCount);

  /// No description provided for @completeTaskDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete parent task?'**
  String get completeTaskDialogTitle;

  /// No description provided for @completeTaskDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This task has incomplete subtasks. Completing it will not complete its subtasks.'**
  String get completeTaskDialogMessage;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @statusTodo.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get statusTodo;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get statusInProgress;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get statusDone;

  /// No description provided for @statusWontDo.
  ///
  /// In en, this message translates to:
  /// **'Won\'t do'**
  String get statusWontDo;

  /// No description provided for @editTaskTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTaskTooltip;

  /// No description provided for @editTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTaskTitle;

  /// No description provided for @priorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priorityLabel;

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

  /// No description provided for @dueDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDateLabel;

  /// No description provided for @noDueDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get noDueDate;

  /// No description provided for @setDueDateButton.
  ///
  /// In en, this message translates to:
  /// **'Set date'**
  String get setDueDateButton;

  /// No description provided for @clearDueDateButton.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get clearDueDateButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @titleRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Title is required.'**
  String get titleRequiredError;

  /// No description provided for @failedToSaveTask.
  ///
  /// In en, this message translates to:
  /// **'Failed to save task: {error}'**
  String failedToSaveTask(String error);

  /// No description provided for @moveToTrashButton.
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get moveToTrashButton;

  /// No description provided for @openTrashTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open trash'**
  String get openTrashTooltip;

  /// No description provided for @trashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashTitle;

  /// No description provided for @trashEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty.'**
  String get trashEmptyTitle;

  /// No description provided for @trashEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Deleted tasks will appear here.'**
  String get trashEmptyBody;

  /// No description provided for @failedToLoadTrash.
  ///
  /// In en, this message translates to:
  /// **'Failed to load trash: {error}'**
  String failedToLoadTrash(String error);

  /// No description provided for @restoreTaskTooltip.
  ///
  /// In en, this message translates to:
  /// **'Restore task'**
  String get restoreTaskTooltip;

  /// No description provided for @undoActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoActionLabel;

  /// No description provided for @undoCompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Task completed.'**
  String get undoCompleteMessage;

  /// No description provided for @undoDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Task moved to trash.'**
  String get undoDeleteMessage;

  /// No description provided for @undoEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Task saved.'**
  String get undoEditMessage;

  /// No description provided for @undoSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Undone.'**
  String get undoSuccessMessage;

  /// No description provided for @undoFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Undo failed: {error}'**
  String undoFailedMessage(String error);

  /// No description provided for @taskSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort tasks'**
  String get taskSortTooltip;

  /// No description provided for @taskSortManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get taskSortManual;

  /// No description provided for @taskSortDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get taskSortDueDate;

  /// No description provided for @taskSortPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get taskSortPriority;

  /// No description provided for @taskSortCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get taskSortCreatedAt;

  /// No description provided for @moveTaskUpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move task up'**
  String get moveTaskUpTooltip;

  /// No description provided for @moveTaskDownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move task down'**
  String get moveTaskDownTooltip;

  /// No description provided for @taskDeletedAt.
  ///
  /// In en, this message translates to:
  /// **'Deleted: {deletedAt}'**
  String taskDeletedAt(String deletedAt);

  /// No description provided for @failedToStartTodori.
  ///
  /// In en, this message translates to:
  /// **'Failed to start Todori: {error}'**
  String failedToStartTodori(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
