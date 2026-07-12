import 'package:todori/src/rust/api.dart' as rust_api;

/// Abstracts the FRB-generated Rust bridge functions behind a plain Dart
/// interface.
///
/// Riverpod providers depend on this interface rather than calling the
/// generated `package:todori/src/rust/api.dart` functions directly. This
/// lets widget tests override [bridgeServiceProvider] (see
/// `src/core/providers.dart`) with an in-memory fake implementation, so the
/// whole screen/provider/router stack can be exercised without loading the
/// native Rust library or calling `initCore`.
abstract class BridgeService {
  Future<rust_api.AccountSessionStateDto> getAccountSessionState();

  Future<rust_api.AccountAuthResultDto> accountRegister({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  });

  Future<rust_api.AccountAuthResultDto> accountLogin({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  });

  Future<void> accountLogout();

  Future<rust_api.SyncStatusDto> getSyncStatus();

  Future<rust_api.SyncStatusDto> syncNow();

  Future<String> getSyncServerUrl();

  Future<void> setSyncServerUrl({required String serverUrl});

  Future<String> getLocalTimeZone();

  /// Creates a list using the caller-provided `sortOrder`.
  Future<rust_api.ListDto> createList({
    required String name,
    required String sortOrder,
  });

  /// Returns active, non-archived lists.
  Future<List<rust_api.ListDto>> getLists();

  /// Returns archived lists.
  Future<List<rust_api.ListDto>> getArchivedLists();

  /// Renames a list.
  Future<rust_api.ListDto> renameList({
    required String listId,
    required String name,
  });

  /// Archives a list.
  Future<rust_api.ListDto> archiveList({required String listId});

  /// Restores an archived list to the active list collection.
  Future<rust_api.ListDto> unarchiveList({required String listId});

  /// Creates a task at the end of its sibling group.
  Future<rust_api.TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
    rust_api.TaskDueInput? due,
    String note = '',
  });

  /// Returns tasks of `listId`.
  Future<List<rust_api.TaskDto>> getTasks({required String listId});

  /// Returns Home smart-view tasks across active lists.
  Future<List<rust_api.HomeTaskDto>> getHomeTasks({
    required int todayStartMs,
    required int tomorrowStartMs,
  });

  /// Returns the number of tasks in `listId`, including completed tasks.
  Future<int> countTasksInList({required String listId});

  /// Updates the editable fields of a task.
  Future<rust_api.TaskDto> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    rust_api.TaskDueInput? due,
  });

  /// Transitions a task's status.
  Future<rust_api.TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  });

  /// Returns the number of descendants below `taskId`.
  Future<int> countTaskDescendants({required String taskId});

  /// Permanently deletes `taskId` and its descendants.
  Future<void> deleteTask({required String taskId});

  /// Permanently deletes `listId` and all of its tasks.
  Future<void> deleteList({required String listId});

  /// Reorders a task within its current sibling group.
  Future<rust_api.TaskDto> reorderTask({
    required String taskId,
    String? previousTaskId,
    String? nextTaskId,
  });

  /// Returns the latest unconsumed task undo entry, if one exists.
  Future<rust_api.TaskUndoDto?> getLatestTaskUndo();

  /// Applies a task undo entry.
  Future<rust_api.TaskDto> undoTaskOperation({required String undoId});

  /// Returns a persisted app setting, if it exists.
  Future<String?> getSetting({required String key});

  /// Persists an app setting.
  Future<void> setSetting({required String key, required String value});

  /// Replaces this task's Phase 1 reminder with a single local reminder.
  Future<rust_api.ReminderDto> setTaskReminder({
    required String taskId,
    required int remindAt,
  });

  /// Clears all reminders for a task and returns the cleared rows.
  Future<List<rust_api.ReminderDto>> clearTaskReminders({
    required String taskId,
  });

  /// Returns all reminders for a task.
  Future<List<rust_api.ReminderDto>> getTaskReminders({required String taskId});

  /// Returns all reminders below a task subtree.
  Future<List<rust_api.ReminderDto>> getTaskSubtreeReminders({
    required String taskId,
  });

  /// Returns all reminders for tasks in a list.
  Future<List<rust_api.ReminderDto>> getListReminders({required String listId});

  /// Returns future reminders for open tasks.
  Future<List<rust_api.ReminderDto>> listPendingReminders({required int nowMs});

  /// Updates a reminder's snooze time.
  Future<rust_api.ReminderDto> snoozeReminder({
    required String reminderId,
    required int snoozedUntil,
  });
}

/// Default [BridgeService] implementation backed by the FRB-generated
/// bindings in `src/rust/api.dart`.
class FrbBridgeService implements BridgeService {
  const FrbBridgeService();

  @override
  Future<rust_api.AccountSessionStateDto> getAccountSessionState() =>
      rust_api.getAccountSessionState();

  @override
  Future<rust_api.AccountAuthResultDto> accountRegister({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  }) => rust_api.accountRegister(
    email: email,
    password: password,
    serverUrl: serverUrl,
    deviceName: deviceName,
  );

  @override
  Future<rust_api.AccountAuthResultDto> accountLogin({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  }) => rust_api.accountLogin(
    email: email,
    password: password,
    serverUrl: serverUrl,
    deviceName: deviceName,
  );

  @override
  Future<void> accountLogout() => rust_api.accountLogout();

  @override
  Future<rust_api.SyncStatusDto> getSyncStatus() => rust_api.getSyncStatus();

  @override
  Future<rust_api.SyncStatusDto> syncNow() => rust_api.syncNow();

  @override
  Future<String> getSyncServerUrl() => rust_api.getSyncServerUrl();

  @override
  Future<void> setSyncServerUrl({required String serverUrl}) =>
      rust_api.setSyncServerUrl(serverUrl: serverUrl);

  @override
  Future<String> getLocalTimeZone() => rust_api.getLocalTimeZone();

  @override
  Future<rust_api.ListDto> createList({
    required String name,
    required String sortOrder,
  }) => rust_api.createList(name: name, sortOrder: sortOrder);

  @override
  Future<List<rust_api.ListDto>> getLists() => rust_api.getLists();

  @override
  Future<List<rust_api.ListDto>> getArchivedLists() =>
      rust_api.getArchivedLists();

  @override
  Future<rust_api.ListDto> renameList({
    required String listId,
    required String name,
  }) => rust_api.renameList(listId: listId, name: name);

  @override
  Future<rust_api.ListDto> archiveList({required String listId}) =>
      rust_api.archiveList(listId: listId);

  @override
  Future<rust_api.ListDto> unarchiveList({required String listId}) =>
      rust_api.unarchiveList(listId: listId);

  @override
  Future<rust_api.TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
    rust_api.TaskDueInput? due,
    String note = '',
  }) => rust_api.createTask(
    listId: listId,
    title: title,
    parentTaskId: parentTaskId,
    due: due,
    note: note.isEmpty ? null : note,
  );

  @override
  Future<List<rust_api.TaskDto>> getTasks({required String listId}) =>
      rust_api.getTasks(listId: listId);

  @override
  Future<List<rust_api.HomeTaskDto>> getHomeTasks({
    required int todayStartMs,
    required int tomorrowStartMs,
  }) => rust_api.getHomeTasks(
    todayStartMs: todayStartMs,
    tomorrowStartMs: tomorrowStartMs,
  );

  @override
  Future<int> countTasksInList({required String listId}) =>
      rust_api.countTasksInList(listId: listId);

  @override
  Future<rust_api.TaskDto> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    rust_api.TaskDueInput? due,
  }) => rust_api.updateTask(
    taskId: taskId,
    title: title,
    note: note,
    priority: priority,
    due: due,
  );

  @override
  Future<rust_api.TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  }) => rust_api.setTaskStatus(
    taskId: taskId,
    status: status,
    closedReason: closedReason,
  );

  @override
  Future<int> countTaskDescendants({required String taskId}) =>
      rust_api.countTaskDescendants(taskId: taskId);

  @override
  Future<void> deleteTask({required String taskId}) =>
      rust_api.deleteTask(taskId: taskId);

  @override
  Future<void> deleteList({required String listId}) =>
      rust_api.deleteList(listId: listId);

  @override
  Future<rust_api.TaskDto> reorderTask({
    required String taskId,
    String? previousTaskId,
    String? nextTaskId,
  }) => rust_api.reorderTask(
    taskId: taskId,
    previousTaskId: previousTaskId,
    nextTaskId: nextTaskId,
  );

  @override
  Future<rust_api.TaskUndoDto?> getLatestTaskUndo() =>
      rust_api.getLatestTaskUndo();

  @override
  Future<rust_api.TaskDto> undoTaskOperation({required String undoId}) =>
      rust_api.undoTaskOperation(undoId: undoId);

  @override
  Future<String?> getSetting({required String key}) =>
      rust_api.getSetting(key: key);

  @override
  Future<void> setSetting({required String key, required String value}) =>
      rust_api.setSetting(key: key, value: value);

  @override
  Future<rust_api.ReminderDto> setTaskReminder({
    required String taskId,
    required int remindAt,
  }) => rust_api.setTaskReminder(taskId: taskId, remindAt: remindAt);

  @override
  Future<List<rust_api.ReminderDto>> clearTaskReminders({
    required String taskId,
  }) => rust_api.clearTaskReminders(taskId: taskId);

  @override
  Future<List<rust_api.ReminderDto>> getTaskReminders({
    required String taskId,
  }) => rust_api.getTaskReminders(taskId: taskId);

  @override
  Future<List<rust_api.ReminderDto>> getTaskSubtreeReminders({
    required String taskId,
  }) => rust_api.getTaskSubtreeReminders(taskId: taskId);

  @override
  Future<List<rust_api.ReminderDto>> getListReminders({
    required String listId,
  }) => rust_api.getListReminders(listId: listId);

  @override
  Future<List<rust_api.ReminderDto>> listPendingReminders({
    required int nowMs,
  }) => rust_api.listPendingReminders(nowMs: nowMs);

  @override
  Future<rust_api.ReminderDto> snoozeReminder({
    required String reminderId,
    required int snoozedUntil,
  }) => rust_api.snoozeReminder(
    reminderId: reminderId,
    snoozedUntil: snoozedUntil,
  );
}
