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
  String get todayTitle => 'Today';

  @override
  String get homeTasksSectionTitle => 'Tasks';

  @override
  String homePendingCount(int count) {
    return '$count pending';
  }

  @override
  String get completedTasksTitle => 'Closed';

  @override
  String completedTasksCount(int count) {
    return '$count closed';
  }

  @override
  String get showCompletedTasksTooltip => 'Show closed tasks';

  @override
  String get hideCompletedTasksTooltip => 'Hide closed tasks';

  @override
  String get homeListMenuTooltip => 'Open lists';

  @override
  String get homeEmptyTitle => 'Start with a list.';

  @override
  String get homeEmptyBody =>
      'Create a list, then Todori will open straight into your tasks.';

  @override
  String get homeNewListButton => 'New list';

  @override
  String get addTaskButton => 'Add task';

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
  String get changeDueDateTooltip => 'Change due date';

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
  String get dueDateLabel => 'Due date';

  @override
  String get noDueDate => 'No due date';

  @override
  String get setDueDateButton => 'Set date';

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
  String failedToStartTodori(String error) {
    return 'Failed to start Todori: $error';
  }
}
