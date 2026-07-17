// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Todori';

  @override
  String get defaultInboxName => 'Inbox';

  @override
  String get defaultListMissing =>
      'Default list is missing. Restart Todori or check local database provisioning.';

  @override
  String get listsTitle => 'Lists';

  @override
  String get listsSectionTitle => 'Lists';

  @override
  String get listsEmpty => 'No lists yet. Tap + to create one.';

  @override
  String get listsEmptyTitle => 'No lists yet.';

  @override
  String get listsEmptyBody => 'Tap + to create one.';

  @override
  String failedToLoadLists(String error) {
    return 'Failed to load lists: $error';
  }

  @override
  String get newListTooltip => 'New list';

  @override
  String get newListTitle => 'New list';

  @override
  String get listActionsTooltip => 'List actions';

  @override
  String get listsMoreMenuTooltip => 'More';

  @override
  String get renameListMenuItem => 'Rename';

  @override
  String get renameListTitle => 'Rename list';

  @override
  String get archiveListMenuItem => 'Archive';

  @override
  String get deleteListMenuItem => 'Delete';

  @override
  String get unarchiveListMenuItem => 'Unarchive';

  @override
  String deleteListDialogTitle(String listName) {
    return 'Delete $listName?';
  }

  @override
  String deleteListDialogMessage(int taskCount) {
    return 'This will permanently delete this list and $taskCount tasks, including completed tasks. This cannot be undone. Archive the list instead if you want to keep history.';
  }

  @override
  String archivedListsSectionTitle(int count) {
    return 'Archived ($count)';
  }

  @override
  String get showArchivedListsTooltip => 'Show archived lists';

  @override
  String get hideArchivedListsTooltip => 'Hide archived lists';

  @override
  String get nameLabel => 'Name';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get deleteButton => 'Delete';

  @override
  String get createButton => 'Create';

  @override
  String get tasksTitle => 'Tasks';

  @override
  String get homeTitle => 'Home';

  @override
  String get calendarTitle => 'Calendar';

  @override
  String get calendarWeekTab => 'Week';

  @override
  String get calendarMonthTab => 'Month';

  @override
  String get calendarPreviousPeriodTooltip => 'Previous period';

  @override
  String get calendarNextPeriodTooltip => 'Next period';

  @override
  String get calendarGoToToday => 'Today';

  @override
  String calendarSelectedDaySemantics(String date) {
    return 'Selected date: $date';
  }

  @override
  String calendarDayTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
      zero: 'No tasks',
    );
    return '$_temp0';
  }

  @override
  String get calendarCompletedTitle => 'Completed';

  @override
  String get calendarShowCompletedTooltip => 'Show completed work';

  @override
  String get calendarHideCompletedTooltip => 'Hide completed work';

  @override
  String get calendarEmptyTitle => 'Nothing planned.';

  @override
  String get calendarEmptyBody =>
      'Choose another day or capture what you want to make time for.';

  @override
  String get calendarLoadFailed => 'Calendar could not be loaded.';

  @override
  String get calendarLoadingSemantics => 'Loading calendar';

  @override
  String get calendarRetryButton => 'Try again';

  @override
  String get calendarDueKind => 'Due';

  @override
  String get calendarScheduledKind => 'Planned';

  @override
  String get calendarCompletedKind => 'Completed';

  @override
  String calendarArchivedListContext(String listName) {
    return '$listName · Archived';
  }

  @override
  String calendarOccurrenceSemantics(
    String title,
    String listName,
    String kind,
    String time,
  ) {
    return '$title, $listName, $kind, $time';
  }

  @override
  String get calendarMoveDueTooltip => 'Move due date';

  @override
  String get calendarMoveScheduledTooltip => 'Move planned date';

  @override
  String calendarMoveOccurrenceSemantics(String kind, String title) {
    return '$kind: change date for $title';
  }

  @override
  String get calendarMoveSheetTitle => 'Change date';

  @override
  String get calendarMoveToToday => 'Today';

  @override
  String get calendarMoveToTomorrow => 'Tomorrow';

  @override
  String get calendarPickDate => 'Choose date…';

  @override
  String get todayTitle => 'Today';

  @override
  String get homeOverdueSectionTitle => 'Overdue';

  @override
  String get homeTomorrowSectionTitle => 'Tomorrow';

  @override
  String get homeUpcomingSectionTitle => 'Upcoming';

  @override
  String get homeTasksSectionTitle => 'Tasks';

  @override
  String homePendingCount(int count) {
    return '$count pending';
  }

  @override
  String get completedTasksTitle => 'Closed';

  @override
  String get showCompletedTasksTooltip => 'Show closed tasks';

  @override
  String get hideCompletedTasksTooltip => 'Hide closed tasks';

  @override
  String get homeListMenuTooltip => 'Open lists';

  @override
  String get homeSmartListTooltip => 'Open Home';

  @override
  String get openSearchTooltip => 'Search tasks';

  @override
  String get searchFieldHint => 'Search tasks and notes';

  @override
  String get searchFieldSemantics => 'Search tasks and notes';

  @override
  String get clearSearchTooltip => 'Clear search';

  @override
  String get searchEmptyTitle => 'Find what you need.';

  @override
  String get searchEmptyBody =>
      'Search task titles and notes across every list.';

  @override
  String get searchNoResultsTitle => 'Nothing found.';

  @override
  String searchNoResultsBody(String query) {
    return 'No tasks match “$query”.';
  }

  @override
  String get searchFailed => 'Search could not be completed.';

  @override
  String get searchLoadingSemantics => 'Searching tasks';

  @override
  String searchArchivedListLabel(String listName) {
    return '$listName · Archived';
  }

  @override
  String searchResultSemantics(String title, String listName, String status) {
    return '$title, $listName, $status';
  }

  @override
  String showHomeSectionTooltip(String section) {
    return 'Show $section tasks';
  }

  @override
  String hideHomeSectionTooltip(String section) {
    return 'Hide $section tasks';
  }

  @override
  String get homeEmptyTitle => 'Start with a list.';

  @override
  String get homeEmptyBody =>
      'Create a list, then Todori will open straight into your tasks.';

  @override
  String get homeNewListButton => 'New list';

  @override
  String get homeClearTitle => 'A little room to breathe.';

  @override
  String get homeClearBody =>
      'Nothing is waiting here. Add a task whenever you are ready.';

  @override
  String get addTaskButton => 'Add task';

  @override
  String get quickAddHint => 'Add task';

  @override
  String get quickAddOpenTooltip => 'Open task creation';

  @override
  String get quickAddOpenSemantics => 'Open task creation sheet';

  @override
  String get quickAddSubmitTooltip => 'Add task';

  @override
  String get quickAddTextFieldSemantics => 'Quick add task title';

  @override
  String get quickAddCreateError => 'Could not add the task.';

  @override
  String get taskCreateTitleHint => 'Add a task...';

  @override
  String get taskCreateListChip => 'List';

  @override
  String get taskCreateListTooltip => 'Choose list';

  @override
  String get taskCreateDueChip => 'Due';

  @override
  String get taskCreateDueTooltip => 'Choose due date';

  @override
  String taskCreateDueChipSemantics(String dueAt) {
    return 'Due: $dueAt';
  }

  @override
  String get taskCreatePlanLabel => 'Plan';

  @override
  String get taskCreatePlanTooltip => 'Set planned start and estimate';

  @override
  String get taskCreatePriorityTooltip => 'Choose priority';

  @override
  String get planNotSet => 'Not planned';

  @override
  String get planSheetTitle => 'Plan';

  @override
  String get plannedStartLabel => 'Planned start';

  @override
  String get setPlannedStartButton => 'Set date and time';

  @override
  String get estimateLabel => 'Estimate';

  @override
  String get estimateNotSet => 'No estimate';

  @override
  String estimateMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get decreaseEstimateTooltip => 'Decrease estimate by 5 minutes';

  @override
  String get increaseEstimateTooltip => 'Increase estimate by 5 minutes';

  @override
  String get clearPlanButton => 'Clear plan';

  @override
  String get planSaveButton => 'Apply plan';

  @override
  String get prioritySheetTitle => 'Priority';

  @override
  String selectedOptionSemantics(String option) {
    return 'Selected: $option';
  }

  @override
  String get tasksEmpty => 'No tasks yet. Tap + to create one.';

  @override
  String get tasksEmptyTitle => 'No tasks yet.';

  @override
  String get tasksEmptyBody => 'Tap + to create one.';

  @override
  String failedToLoadTasks(String error) {
    return 'Failed to load tasks: $error';
  }

  @override
  String get newTaskTooltip => 'New task';

  @override
  String get newTaskTitle => 'New task';

  @override
  String get titleLabel => 'Title';

  @override
  String get noteLabel => 'Note';

  @override
  String get taskDetailTitle => 'Task detail';

  @override
  String failedToLoadTask(String error) {
    return 'Failed to load task: $error';
  }

  @override
  String get taskNotFound => 'Task not found.';

  @override
  String taskPriority(String priority) {
    return 'Priority: $priority';
  }

  @override
  String taskDueAt(String dueAt) {
    return '$dueAt';
  }

  @override
  String taskRowStatusSemantics(String status) {
    return 'Status: $status';
  }

  @override
  String taskRowDueSemantics(String dueAt) {
    return 'Due: $dueAt';
  }

  @override
  String taskRowListSemantics(String listName) {
    return 'List: $listName';
  }

  @override
  String taskRowSubtaskLevelSemantics(int level) {
    return 'Subtask level $level';
  }

  @override
  String get taskRowOpenHint => 'Double tap to open task';

  @override
  String get dueToday => 'Today';

  @override
  String get dueTomorrow => 'Tomorrow';

  @override
  String taskDueOverdue(String dueAt) {
    return 'Overdue: $dueAt';
  }

  @override
  String taskCreatedAt(String createdAt) {
    return 'Created at: $createdAt';
  }

  @override
  String get addNotePlaceholder => 'Add note';

  @override
  String get editTaskTitleSemantics => 'Edit task title';

  @override
  String get editTaskNoteSemantics => 'Edit task note';

  @override
  String parentTaskLinkTooltip(String title) {
    return 'Open parent task: $title';
  }

  @override
  String parentTaskLinkSemantics(String title) {
    return 'Parent task: $title';
  }

  @override
  String get changeDueDateTooltip => 'Change due date';

  @override
  String get reminderChipEmpty => 'Reminder';

  @override
  String get reminderChipTooltipSet => 'Set reminder';

  @override
  String get reminderChipTooltipChange => 'Change reminder';

  @override
  String get clearReminderButton => 'Clear reminder';

  @override
  String get reminderPermissionDenied =>
      'Notifications are off. The reminder was saved, but Todori could not schedule a local notification.';

  @override
  String failedToSaveReminder(String error) {
    return 'Failed to save reminder: $error';
  }

  @override
  String get reminderNotificationTitle => 'Todori reminder';

  @override
  String get reminderNotificationBody => 'A task reminder is due.';

  @override
  String get reminderSnoozeOneHourAction => '+1 hour';

  @override
  String get changePriorityTooltip => 'Change priority';

  @override
  String get subtasksTitle => 'Subtasks';

  @override
  String get subtasksEmpty => 'No subtasks yet.';

  @override
  String get addSubtaskButton => 'Add subtask';

  @override
  String get newSubtaskTitle => 'New subtask';

  @override
  String subtaskProgress(int doneCount, int totalCount) {
    return '$doneCount/$totalCount';
  }

  @override
  String get completeTaskDialogTitle => 'Complete parent task?';

  @override
  String get completeTaskDialogMessage =>
      'This task has incomplete subtasks. Completing it will not complete its subtasks.';

  @override
  String get wontDoTaskDialogTitle => 'Close parent as won\'t do?';

  @override
  String get wontDoTaskDialogMessage =>
      'This task has incomplete subtasks. Closing it as won\'t do will not close its subtasks.';

  @override
  String get continueButton => 'Continue';

  @override
  String get statusTodo => 'To do';

  @override
  String get statusInProgress => 'In progress';

  @override
  String get statusDone => 'Done';

  @override
  String get statusWontDo => 'Won\'t do';

  @override
  String get editTaskTooltip => 'Edit task';

  @override
  String get taskActionsTooltip => 'Task actions';

  @override
  String get completeTaskTooltip => 'Mark task done';

  @override
  String get markTaskDoneMenuItem => 'Mark done';

  @override
  String get markTaskWontDoMenuItem => 'Mark won\'t do';

  @override
  String get reopenTaskTooltip => 'Reopen task';

  @override
  String get reopenTaskMenuItem => 'Reopen';

  @override
  String get editTaskTitle => 'Edit task';

  @override
  String get priorityLabel => 'Priority';

  @override
  String get priorityNone => 'None';

  @override
  String get priorityLow => 'Low';

  @override
  String get priorityMedium => 'Medium';

  @override
  String get priorityHigh => 'High';

  @override
  String get dueDateLabel => 'Due';

  @override
  String get noDueDate => 'No due date';

  @override
  String get setDueDateButton => 'Set date';

  @override
  String get setDueDateTimeButton => 'Set date and time';

  @override
  String get clearDueDateButton => 'Clear date';

  @override
  String get saveButton => 'Save';

  @override
  String get titleRequiredError => 'Title is required.';

  @override
  String failedToSaveTask(String error) {
    return 'Failed to save task: $error';
  }

  @override
  String get deleteTaskMenuItem => 'Delete';

  @override
  String get deleteTaskDialogTitle => 'Delete task?';

  @override
  String get deleteTaskDialogMessage =>
      'This task will be permanently deleted and cannot be recovered.';

  @override
  String deleteTaskDialogMessageWithDescendants(int descendantCount) {
    return 'This task and $descendantCount subtasks will be permanently deleted and cannot be recovered.';
  }

  @override
  String get undoActionLabel => 'Undo';

  @override
  String get undoCompleteMessage => 'Task completed.';

  @override
  String get undoCloseMessage => 'Task closed.';

  @override
  String get undoEditMessage => 'Task saved.';

  @override
  String get undoSuccessMessage => 'Undone.';

  @override
  String undoFailedMessage(String error) {
    return 'Undo failed: $error';
  }

  @override
  String get taskSortTooltip => 'Sort tasks';

  @override
  String get taskSortManual => 'Manual';

  @override
  String get taskSortDueDate => 'Due date';

  @override
  String get taskSortPriority => 'Priority';

  @override
  String get taskSortCreatedAt => 'Created';

  @override
  String get moveTaskUpTooltip => 'Move task up';

  @override
  String get moveTaskDownTooltip => 'Move task down';

  @override
  String get accountTitle => 'Account';

  @override
  String get navigationYouLabel => 'You';

  @override
  String get accountLoadFailed => 'Could not load account state.';

  @override
  String get accountLoginTab => 'Log in';

  @override
  String get accountRegisterTab => 'Register';

  @override
  String get accountEmailLabel => 'Email';

  @override
  String get accountPasswordLabel => 'Password';

  @override
  String get accountLoginButton => 'Log in';

  @override
  String get accountRegisterButton => 'Register';

  @override
  String get accountLogoutButton => 'Log out';

  @override
  String get accountServerUrlLabel => 'Server URL';

  @override
  String get accountSaveServerUrlTooltip => 'Save server URL';

  @override
  String get accountRequestFailed => 'Account request failed.';

  @override
  String get accountSyncTitle => 'Sync';

  @override
  String get accountSyncNotSignedIn => 'Sync is off.';

  @override
  String get accountSyncIdle => 'Ready';

  @override
  String get accountSyncRunning => 'Syncing';

  @override
  String get accountSyncFailed => 'Sync failed';

  @override
  String accountSyncLastSuccess(String time) {
    return 'Last synced: $time';
  }

  @override
  String get accountSyncNever => 'Never';

  @override
  String get accountSyncNowButton => 'Sync now';

  @override
  String get accountSyncNowTooltip => 'Sync now';

  @override
  String get organizationSafetyOpenButton => 'Verify organization member';

  @override
  String get organizationSafetyTitle => 'Safety number';

  @override
  String get organizationSafetyBody =>
      'Compare this number or QR code with the other account through a separate trusted channel. Organization keys are not delivered until both accounts confirm the same value.';

  @override
  String get organizationTenantIdLabel => 'Organization ID';

  @override
  String get organizationMemberIdLabel => 'Member account ID';

  @override
  String get organizationSafetyLoadButton => 'Show Safety number';

  @override
  String get organizationSafetyQrSemantics => 'Safety number QR code';

  @override
  String get organizationSafetyVerified => 'Verified by both accounts';

  @override
  String get organizationSafetyUnverified =>
      'Not yet verified by both accounts';

  @override
  String get organizationSafetyComparedOutOfBand =>
      'I compared this value through a separate trusted channel';

  @override
  String get organizationSafetyConfirmButton => 'Confirm this Safety number';

  @override
  String get organizationSafetyFailed =>
      'Could not verify the Safety number. Reload it and compare again.';

  @override
  String get onboardingWelcomeTitle => 'Make room for what matters';

  @override
  String get onboardingWelcomeBody =>
      'A calm place for plans, small promises, and the next thing worth doing. No scores. No noise.';

  @override
  String get onboardingWelcomeArtworkSemantics =>
      'A quiet leaf representing Todori';

  @override
  String get onboardingPrivacyTitle => 'Private by design';

  @override
  String get onboardingPrivacyBody =>
      'Your local database is encrypted on this device. When you choose to sync, task content is encrypted before it leaves.';

  @override
  String get onboardingPrivacyNote =>
      'Without sync, your tasks live only on this device and may be unrecoverable if the device is lost or the app is removed.';

  @override
  String get onboardingPrivacyArtworkSemantics =>
      'A shield representing local protection and encrypted sync';

  @override
  String get onboardingBeginTitle => 'Begin with one small thing';

  @override
  String get onboardingBeginBody =>
      'Add what needs your attention. Todori stays quiet until you need it.';

  @override
  String get onboardingBeginArtworkSemantics =>
      'A settled check mark representing a completed task';

  @override
  String get onboardingStartButton => 'Start gently';

  @override
  String get onboardingSaveFailed =>
      'Todori couldn\'t save this choice. Try again to continue.';

  @override
  String get onboardingLoadFailed =>
      'Todori couldn\'t read its local settings.';

  @override
  String get retryButton => 'Try again';

  @override
  String onboardingPagePosition(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String get focusTitle => 'Focus';

  @override
  String get focusSetupTitle => 'Choose how to focus';

  @override
  String get focusSetupBody => 'Stay with one task. The rest can wait.';

  @override
  String get focusPomodoroMode => 'Pomodoro';

  @override
  String get focusStopwatchMode => 'Stopwatch';

  @override
  String focusPomodoroSummary(int work, int breakMinutes) {
    return '$work min focus · $breakMinutes min break';
  }

  @override
  String get focusStopwatchSummary => 'Open-ended, with pause and resume';

  @override
  String get focusStartButton => 'Start focus';

  @override
  String get focusSettingsButton => 'Pomodoro settings';

  @override
  String get focusSettingsTitle => 'Pomodoro rhythm';

  @override
  String get focusWorkMinutesLabel => 'Focus';

  @override
  String get focusShortBreakMinutesLabel => 'Short break';

  @override
  String get focusLongBreakMinutesLabel => 'Long break';

  @override
  String get focusLongBreakEveryLabel => 'Long break after';

  @override
  String get focusNotificationsLabel => 'Completion notification';

  @override
  String get focusNotificationsBody =>
      'Best effort while Todori is in the background';

  @override
  String focusWorkIntervals(int count) {
    return '$count focus sessions';
  }

  @override
  String get focusRestoring => 'Restoring your focus session…';

  @override
  String get focusLoadFailed => 'Todori couldn\'t restore this focus session.';

  @override
  String get focusActiveConflictTitle => 'Another focus session is active';

  @override
  String get focusActiveConflictBody =>
      'Finish or discard the current session before starting this task.';

  @override
  String get focusRunningState => 'Focusing';

  @override
  String get focusPausedState => 'Paused';

  @override
  String get focusWorkPhase => 'Focus session';

  @override
  String get focusShortBreakPhase => 'Short break';

  @override
  String get focusLongBreakPhase => 'Long break';

  @override
  String get focusBreakPrompt => 'Take a breath.';

  @override
  String focusElapsedLabel(String time) {
    return 'Elapsed $time';
  }

  @override
  String get focusPauseButton => 'Pause';

  @override
  String get focusResumeButton => 'Resume';

  @override
  String get focusSessionOptionsButton => 'Session options';

  @override
  String get focusAddTimeButton => 'Add 5 minutes';

  @override
  String get focusFinishButton => 'Finish';

  @override
  String get focusFinishSessionButton => 'Finish session';

  @override
  String get focusEndBreakButton => 'End break';

  @override
  String get focusSaveAndExitButton => 'Save and exit';

  @override
  String get focusDiscardButton => 'Discard';

  @override
  String get focusDiscardTitle => 'Discard this session?';

  @override
  String get focusDiscardBody =>
      'This session will end without saving work time.';

  @override
  String get focusCompleteTaskButton => 'Complete task';

  @override
  String get focusFinishedTitle => 'Focus recorded';

  @override
  String get focusFinishedSummary => 'Focused work recorded.';

  @override
  String focusFinishedBody(String time) {
    return '$time of focused work recorded.';
  }

  @override
  String get focusBreakFinishedTitle => 'Break complete';

  @override
  String get focusBreakFinishedBody =>
      'Return when you\'re ready for the next focus session.';

  @override
  String get focusStartBreakButton => 'Start break';

  @override
  String get focusKeepSessionButton => 'Keep focusing';

  @override
  String get focusDoneButton => 'Done';

  @override
  String get focusActionFailed =>
      'Couldn\'t update this focus session. Try again.';

  @override
  String get focusTaskCompleteFailed =>
      'The session was saved, but the task could not be completed. Try completing it again.';

  @override
  String get focusEstimateActualLabel => 'Focus time';

  @override
  String focusEstimateActualValue(String actual, String estimate) {
    return '$actual actual · $estimate estimated';
  }

  @override
  String focusActualOnlyValue(String actual) {
    return '$actual recorded';
  }

  @override
  String get focusNoActualValue => 'No work recorded yet';

  @override
  String get timerNotificationTitle => 'Focus time is complete';

  @override
  String get timerNotificationBody =>
      'Open Todori to continue your focus rhythm.';

  @override
  String get billingTitle => 'Pro';

  @override
  String get billingSubscriptionBody =>
      'Pro includes E2EE sync and encrypted cloud backup. Cancel anytime in Apple subscriptions.';

  @override
  String get billingStatusFree => 'Free';

  @override
  String get billingStatusTrial => 'Trial';

  @override
  String get billingStatusActive => 'Active';

  @override
  String get billingStatusGrace => 'Payment grace period';

  @override
  String get billingStatusExpired => 'Expired';

  @override
  String get billingStatusRevoked => 'Revoked';

  @override
  String get billingMonthlyLabel => 'Monthly';

  @override
  String get billingYearlyLabel => 'Yearly';

  @override
  String get billingPurchaseButton => 'Start Pro';

  @override
  String get billingRestoreButton => 'Restore purchases';

  @override
  String get billingManageButton => 'Manage subscription';

  @override
  String get billingUnavailable => 'Billing is unavailable right now.';

  @override
  String get billingCancelled => 'Purchase cancelled.';

  @override
  String get billingPending =>
      'Purchase pending. Pro will activate after Apple confirms payment.';

  @override
  String get billingFailed => 'Purchase couldn\'t be completed.';

  @override
  String get billingRestored => 'Purchase status refreshed.';

  @override
  String billingPriceSemantics(String period, String price) {
    return '$period, $price';
  }

  @override
  String get backButtonTooltip => 'Back';

  @override
  String get templatesTitle => 'Templates';

  @override
  String templatesLoadFailed(String error) {
    return 'Templates could not be loaded: $error';
  }

  @override
  String get templatesEmptyTitle => 'No templates yet';

  @override
  String get templatesEmptyBody => 'Open a task and choose Save as template.';

  @override
  String get templateActionsTooltip => 'Template actions';

  @override
  String get editButton => 'Edit';

  @override
  String get replaceTemplateSnapshotMenuItem => 'Replace contents';

  @override
  String templateTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String get createFromTemplateButton => 'Create tasks';

  @override
  String get addScheduleTooltip => 'Add schedule';

  @override
  String get templateCreatedMessage => 'Tasks created from template.';

  @override
  String get replaceTemplateSnapshotTitle => 'Replace template contents';

  @override
  String get sourceTaskIdLabel => 'Source task ID';

  @override
  String get replaceButton => 'Replace';

  @override
  String deleteTemplateDialogTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteTemplateDialogBody =>
      'Its schedules will also be deleted. Tasks already created will stay unchanged.';

  @override
  String get deleteScheduleDialogTitle => 'Delete schedule?';

  @override
  String get deleteScheduleDialogBody =>
      'Tasks already created will stay unchanged.';

  @override
  String get scheduleEndedLabel => 'Ended';

  @override
  String scheduleSemantics(String rule, String next) {
    return 'Schedule $rule, next $next';
  }

  @override
  String scheduleStreak(int count) {
    return '$count streak';
  }

  @override
  String get scheduleActionsTooltip => 'Schedule actions';

  @override
  String get pauseScheduleMenuItem => 'Pause';

  @override
  String get resumeScheduleMenuItem => 'Resume';

  @override
  String get editTemplateTitle => 'Edit template';

  @override
  String get defaultListLabel => 'Default list';

  @override
  String get inboxFallbackLabel => 'Inbox fallback';

  @override
  String get newScheduleTitle => 'New schedule';

  @override
  String get editScheduleTitle => 'Edit schedule';

  @override
  String get schedulePresetLabel => 'Repeat';

  @override
  String get dailyPreset => 'Every day';

  @override
  String get weeklyPreset => 'Every week on this weekday';

  @override
  String get monthlyPreset => 'Every month on this date';

  @override
  String get advancedPreset => 'Advanced RRULE';

  @override
  String get rruleLabel => 'RRULE';

  @override
  String get scheduleStartsAtLabel => 'Starts';

  @override
  String get timeZoneLabel => 'Time zone';

  @override
  String get scheduleEnabledLabel => 'Schedule enabled';

  @override
  String get scheduleValidationFailed =>
      'Check the recurrence rule, start, and time zone.';

  @override
  String get saveAsTemplateMenuItem => 'Save as template';

  @override
  String get saveAsTemplateTitle => 'Save as template';

  @override
  String get templateSavedMessage => 'Template saved.';

  @override
  String failedToStartTodori(String error) {
    return 'Failed to start Todori: $error';
  }
}
