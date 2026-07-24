import 'package:taskveil/src/rust/api.dart' as rust_api;

/// Abstracts the FRB-generated Rust bridge functions behind a plain Dart
/// interface.
///
/// Riverpod providers depend on this interface rather than calling the
/// generated `package:taskveil/src/rust/api.dart` functions directly. This
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

  Future<rust_api.OrganizationSafetyStateDto> organizationSafetyNumber({
    required String tenantId,
    required String memberUserId,
  });

  Future<rust_api.OrganizationSafetyStateDto> confirmOrganizationSafetyNumber({
    required String tenantId,
    required String memberUserId,
    required String digest,
  });

  Future<rust_api.SyncStatusDto> getSyncStatus();

  Future<rust_api.SyncStatusDto> syncNow();

  Future<rust_api.SyncNowOutcomeDto> syncNowOutcome() async =>
      rust_api.SyncNowOutcomeDto.synced(status: await syncNow());

  Future<rust_api.BillingStateDto> billingBootstrap() =>
      Future.error(UnimplementedError('billingBootstrap'));

  Future<rust_api.BillingStateDto> refreshBilling() =>
      Future.error(UnimplementedError('refreshBilling'));

  Future<rust_api.BillingStateDto?> getCachedBilling() async => null;

  Future<rust_api.RealtimeTicketDto> getRealtimeTicket();

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

  Future<List<rust_api.TemplateDto>> getTemplates() =>
      Future.error(UnimplementedError('getTemplates'));

  Future<List<rust_api.TaskSeriesDto>> getTaskSeries() =>
      Future.error(UnimplementedError('getTaskSeries'));

  Future<String> validateRecurrenceRule({
    required String rrule,
    required int startsAt,
    required String timeZone,
  }) => Future.error(UnimplementedError('validateRecurrenceRule'));

  Future<rust_api.TemplateDto> saveTaskAsTemplate({
    required String taskId,
    required String name,
    String? defaultListId,
  }) => Future.error(UnimplementedError('saveTaskAsTemplate'));

  Future<rust_api.TemplateDto> createTemplate({
    required String name,
    String? defaultListId,
    required List<rust_api.TaskBlueprintNodeDto> nodes,
  }) => Future.error(UnimplementedError('createTemplate'));

  Future<rust_api.TemplateDto> updateTemplate({
    required String templateId,
    required String name,
    String? defaultListId,
    required List<rust_api.TaskBlueprintNodeDto> nodes,
  }) => Future.error(UnimplementedError('updateTemplate'));

  Future<rust_api.TemplateDto> replaceTemplateBlueprint({
    required String templateId,
    required String taskId,
  }) => Future.error(UnimplementedError('replaceTemplateBlueprint'));

  Future<List<rust_api.TaskDto>> instantiateTemplate({
    required String templateId,
  }) => Future.error(UnimplementedError('instantiateTemplate'));

  Future<rust_api.TaskSeriesDto> createTaskSeriesFromTemplate({
    required String templateId,
    required String rrule,
    required int startsAt,
    required String timeZone,
  }) => Future.error(UnimplementedError('createTaskSeriesFromTemplate'));

  Future<rust_api.TaskSeriesDto> createTaskSeriesFromTask({
    required String taskId,
    String? targetListId,
    required String rrule,
    required int startsAt,
    required String timeZone,
  }) => Future.error(UnimplementedError('createTaskSeriesFromTask'));

  Future<rust_api.TaskSeriesDto> updateTaskSeries({
    required String seriesId,
    required String rrule,
    required int startsAt,
    required String timeZone,
    required bool enabled,
  }) => Future.error(UnimplementedError('updateTaskSeries'));

  Future<void> deleteTaskSeries({required String seriesId}) =>
      Future.error(UnimplementedError('deleteTaskSeries'));

  Future<void> deleteTemplate({required String templateId}) =>
      Future.error(UnimplementedError('deleteTemplate'));

  Future<rust_api.SettlementSummaryDto> settleDueSeries({required int atMs}) =>
      Future.error(UnimplementedError('settleDueSeries'));

  Future<rust_api.StreakDto> getTaskSeriesStreak({
    required String seriesId,
    required int atMs,
  }) => Future.error(UnimplementedError('getTaskSeriesStreak'));

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
    int priority = 0,
    int? scheduledAt,
    int? estimatedMinutes,
  });

  /// Returns tasks of `listId`.
  Future<List<rust_api.TaskDto>> getTasks({required String listId});

  /// Returns the single durable, device-local active timer session.
  Future<rust_api.ActiveTimerSessionDto?> getActiveTimerSession();

  /// Starts [session] only when there is no other active session.
  Future<rust_api.ActiveTimerStartOutcomeDto> startActiveTimerSession({
    required rust_api.ActiveTimerSessionDto session,
  });

  /// Persists a valid same-identity pause, resume, or target extension.
  Future<void> updateActiveTimerSession({
    required rust_api.ActiveTimerSessionDto session,
  });

  /// Returns the pause-aware wall-clock instant at which a Pomodoro ends.
  Future<DateTime> pomodoroTargetReachedAt({
    required rust_api.ActiveTimerSessionDto session,
  });

  /// Clears the active session only when its identity still matches.
  Future<bool> discardActiveTimerSession({required String expectedSessionId});

  /// Atomically stores a work result and clears its matching active session.
  Future<bool> finishActiveTimerSession({
    required rust_api.CompletedTimerSessionDto session,
  });

  /// Returns immutable, synchronized work history for [taskId].
  Future<List<rust_api.CompletedTimerSessionDto>> getCompletedTimerSessions({
    required String taskId,
  });

  /// Searches task title and note using the local FTS5 prefix query.
  Future<List<rust_api.TaskDto>> searchTasks({required String query});

  /// Returns Home smart-view tasks across active lists.
  Future<List<rust_api.HomeTaskDto>> getHomeTasks({
    required int todayStartMs,
    required int tomorrowStartMs,
  });

  /// Returns typed task occurrences in a half-open calendar range.
  Future<List<rust_api.CalendarOccurrenceDto>> getCalendarOccurrences({
    required rust_api.CalendarRangeInput range,
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
    int? scheduledAt,
    int? estimatedMinutes,
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

  /// Deletes `listId` and moves its tasks to the default Inbox.
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

  /// Adds a local reminder to a task.
  Future<rust_api.ReminderDto> createTaskReminder({
    required String taskId,
    required int remindAt,
  });

  /// Changes one reminder while preserving its identity.
  Future<rust_api.ReminderDto> updateReminder({
    required String reminderId,
    required int remindAt,
  });

  /// Deletes one reminder and returns the deleted row.
  Future<rust_api.ReminderDto> deleteReminder({required String reminderId});

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
  Future<rust_api.OrganizationSafetyStateDto> organizationSafetyNumber({
    required String tenantId,
    required String memberUserId,
  }) => rust_api.organizationSafetyNumber(
    tenantId: tenantId,
    memberUserId: memberUserId,
  );

  @override
  Future<rust_api.OrganizationSafetyStateDto> confirmOrganizationSafetyNumber({
    required String tenantId,
    required String memberUserId,
    required String digest,
  }) => rust_api.confirmOrganizationSafetyNumber(
    tenantId: tenantId,
    memberUserId: memberUserId,
    digest: digest,
  );

  @override
  Future<rust_api.SyncStatusDto> getSyncStatus() => rust_api.getSyncStatus();

  @override
  Future<rust_api.SyncStatusDto> syncNow() => rust_api.syncNow();

  @override
  Future<rust_api.SyncNowOutcomeDto> syncNowOutcome() =>
      rust_api.syncNowOutcome();

  @override
  Future<rust_api.BillingStateDto> billingBootstrap() =>
      rust_api.billingBootstrap();

  @override
  Future<rust_api.BillingStateDto> refreshBilling() =>
      rust_api.refreshBilling();

  @override
  Future<rust_api.BillingStateDto?> getCachedBilling() =>
      rust_api.getCachedBilling();

  @override
  Future<rust_api.RealtimeTicketDto> getRealtimeTicket() =>
      rust_api.getRealtimeTicket();

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
  Future<List<rust_api.TemplateDto>> getTemplates() => rust_api.getTemplates();

  @override
  Future<List<rust_api.TaskSeriesDto>> getTaskSeries() =>
      rust_api.getTaskSeries();

  @override
  Future<String> validateRecurrenceRule({
    required String rrule,
    required int startsAt,
    required String timeZone,
  }) => rust_api.validateRecurrenceRule(
    rrule: rrule,
    startsAt: startsAt,
    timeZone: timeZone,
  );

  @override
  Future<rust_api.TemplateDto> saveTaskAsTemplate({
    required String taskId,
    required String name,
    String? defaultListId,
  }) => rust_api.saveTaskAsTemplate(
    taskId: taskId,
    name: name,
    defaultListId: defaultListId,
  );

  @override
  Future<rust_api.TemplateDto> createTemplate({
    required String name,
    String? defaultListId,
    required List<rust_api.TaskBlueprintNodeDto> nodes,
  }) => rust_api.createTemplate(
    name: name,
    defaultListId: defaultListId,
    nodes: nodes,
  );

  @override
  Future<rust_api.TemplateDto> updateTemplate({
    required String templateId,
    required String name,
    String? defaultListId,
    required List<rust_api.TaskBlueprintNodeDto> nodes,
  }) => rust_api.updateTemplate(
    templateId: templateId,
    name: name,
    defaultListId: defaultListId,
    nodes: nodes,
  );

  @override
  Future<rust_api.TemplateDto> replaceTemplateBlueprint({
    required String templateId,
    required String taskId,
  }) =>
      rust_api.replaceTemplateBlueprint(templateId: templateId, taskId: taskId);

  @override
  Future<List<rust_api.TaskDto>> instantiateTemplate({
    required String templateId,
  }) => rust_api.instantiateTemplate(templateId: templateId);

  @override
  Future<rust_api.TaskSeriesDto> createTaskSeriesFromTemplate({
    required String templateId,
    required String rrule,
    required int startsAt,
    required String timeZone,
  }) => rust_api.createTaskSeriesFromTemplate(
    templateId: templateId,
    rrule: rrule,
    startsAt: startsAt,
    timeZone: timeZone,
  );

  @override
  Future<rust_api.TaskSeriesDto> createTaskSeriesFromTask({
    required String taskId,
    String? targetListId,
    required String rrule,
    required int startsAt,
    required String timeZone,
  }) => rust_api.createTaskSeriesFromTask(
    taskId: taskId,
    targetListId: targetListId,
    rrule: rrule,
    startsAt: startsAt,
    timeZone: timeZone,
  );

  @override
  Future<rust_api.TaskSeriesDto> updateTaskSeries({
    required String seriesId,
    required String rrule,
    required int startsAt,
    required String timeZone,
    required bool enabled,
  }) => rust_api.updateTaskSeries(
    seriesId: seriesId,
    rrule: rrule,
    startsAt: startsAt,
    timeZone: timeZone,
    enabled: enabled,
  );

  @override
  Future<void> deleteTaskSeries({required String seriesId}) =>
      rust_api.deleteTaskSeries(seriesId: seriesId);

  @override
  Future<void> deleteTemplate({required String templateId}) =>
      rust_api.deleteTemplate(templateId: templateId);

  @override
  Future<rust_api.SettlementSummaryDto> settleDueSeries({required int atMs}) =>
      rust_api.settleDueSeries(atMs: atMs);

  @override
  Future<rust_api.StreakDto> getTaskSeriesStreak({
    required String seriesId,
    required int atMs,
  }) => rust_api.getTaskSeriesStreak(seriesId: seriesId, atMs: atMs);

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
    int priority = 0,
    int? scheduledAt,
    int? estimatedMinutes,
  }) => rust_api.createTask(
    listId: listId,
    title: title,
    parentTaskId: parentTaskId,
    due: due,
    note: note.isEmpty ? null : note,
    priority: priority,
    scheduledAt: scheduledAt,
    estimatedMinutes: estimatedMinutes,
  );

  @override
  Future<List<rust_api.TaskDto>> getTasks({required String listId}) =>
      rust_api.getTasks(listId: listId);

  @override
  Future<rust_api.ActiveTimerSessionDto?> getActiveTimerSession() =>
      rust_api.getActiveTimerSession();

  @override
  Future<rust_api.ActiveTimerStartOutcomeDto> startActiveTimerSession({
    required rust_api.ActiveTimerSessionDto session,
  }) => rust_api.startActiveTimerSession(session: session);

  @override
  Future<void> updateActiveTimerSession({
    required rust_api.ActiveTimerSessionDto session,
  }) => rust_api.updateActiveTimerSession(session: session);

  @override
  Future<DateTime> pomodoroTargetReachedAt({
    required rust_api.ActiveTimerSessionDto session,
  }) => rust_api.pomodoroTargetReachedAt(session: session);

  @override
  Future<bool> discardActiveTimerSession({required String expectedSessionId}) =>
      rust_api.discardActiveTimerSession(expectedSessionId: expectedSessionId);

  @override
  Future<bool> finishActiveTimerSession({
    required rust_api.CompletedTimerSessionDto session,
  }) => rust_api.finishActiveTimerSession(session: session);

  @override
  Future<List<rust_api.CompletedTimerSessionDto>> getCompletedTimerSessions({
    required String taskId,
  }) => rust_api.getCompletedTimerSessions(taskId: taskId);

  @override
  Future<List<rust_api.TaskDto>> searchTasks({required String query}) =>
      rust_api.searchTasks(query: query);

  @override
  Future<List<rust_api.HomeTaskDto>> getHomeTasks({
    required int todayStartMs,
    required int tomorrowStartMs,
  }) => rust_api.getHomeTasks(
    todayStartMs: todayStartMs,
    tomorrowStartMs: tomorrowStartMs,
  );

  @override
  Future<List<rust_api.CalendarOccurrenceDto>> getCalendarOccurrences({
    required rust_api.CalendarRangeInput range,
  }) => rust_api.getCalendarOccurrences(range: range);

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
    int? scheduledAt,
    int? estimatedMinutes,
  }) => rust_api.updateTask(
    taskId: taskId,
    title: title,
    note: note,
    priority: priority,
    due: due,
    scheduledAt: scheduledAt,
    estimatedMinutes: estimatedMinutes,
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
  Future<rust_api.ReminderDto> createTaskReminder({
    required String taskId,
    required int remindAt,
  }) => rust_api.createTaskReminder(taskId: taskId, remindAt: remindAt);

  @override
  Future<rust_api.ReminderDto> updateReminder({
    required String reminderId,
    required int remindAt,
  }) => rust_api.updateReminder(reminderId: reminderId, remindAt: remindAt);

  @override
  Future<rust_api.ReminderDto> deleteReminder({required String reminderId}) =>
      rust_api.deleteReminder(reminderId: reminderId);

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
