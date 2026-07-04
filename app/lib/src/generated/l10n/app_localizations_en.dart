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
  String get listsTitle => 'Lists';

  @override
  String get listsEmpty => 'No lists yet. Tap + to create one.';

  @override
  String failedToLoadLists(String error) {
    return 'Failed to load lists: $error';
  }

  @override
  String get newListTooltip => 'New list';

  @override
  String get newListTitle => 'New list';

  @override
  String get nameLabel => 'Name';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get createButton => 'Create';

  @override
  String get tasksTitle => 'Tasks';

  @override
  String get tasksEmpty => 'No tasks yet. Tap + to create one.';

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
  String taskStatus(String status) {
    return 'Status: $status';
  }

  @override
  String taskPriority(int priority) {
    return 'Priority: $priority';
  }

  @override
  String taskDueAt(String dueAt) {
    return 'Due: $dueAt';
  }

  @override
  String taskCreatedAt(int createdAt) {
    return 'Created at: $createdAt';
  }

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
    return 'Progress: $doneCount/$totalCount';
  }

  @override
  String get completeTaskDialogTitle => 'Complete parent task?';

  @override
  String get completeTaskDialogMessage =>
      'This task has incomplete subtasks. Completing it will not complete its subtasks.';

  @override
  String get continueButton => 'Continue';

  @override
  String get editTaskTooltip => 'Edit task';

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
  String get moveToTrashButton => 'Move to trash';

  @override
  String failedToStartTodori(String error) {
    return 'Failed to start Todori: $error';
  }
}
