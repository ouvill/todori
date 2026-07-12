import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/core/task_due.dart';
import 'package:todori/src/core/providers.dart'
    show
        defaultSyncServerUrl,
        onboardingCompletedSettingKey,
        syncServerUrlSettingKey;
import 'package:todori/src/rust/api.dart';

TaskDueDto testDateOnlyDueFromMillis(int value) =>
    dateOnlyDue(DateTime.fromMillisecondsSinceEpoch(value));

TaskDueDto testDateTimeDueFromMillis(int value, {String timeZone = 'UTC'}) =>
    dateTimeDueFromInstant(
      DateTime.fromMillisecondsSinceEpoch(value),
      timeZone: timeZone,
    );

/// In-memory fake [BridgeService].
///
/// Widget tests use this instead of [FrbBridgeService] so the whole
/// screen/provider/router skeleton can be exercised without the native Rust
/// library and without calling `initCore`.
class FakeBridgeService implements BridgeService {
  FakeBridgeService({bool onboardingCompleted = true})
    : _settings = {if (onboardingCompleted) onboardingCompletedSettingKey: '1'};

  final List<ListDto> _lists = [];
  final List<TaskDto> _tasks = [];
  final List<ReminderDto> _reminders = [];
  final List<FakeTaskUndoEntry> _undoEntries = [];
  final Map<String, String> _settings;
  final List<void Function()> _pendingSyncMutations = [];
  final List<FakeReorderCall> reorderCalls = [];
  int syncNowCalls = 0;
  AccountSessionStateDto _accountSession = const AccountSessionStateDto(
    loggedIn: false,
  );
  SyncStatusDto _syncStatus = const SyncStatusDto(
    loggedIn: false,
    running: false,
    pushedCount: 0,
    pushAckedCount: 0,
    pushSupersededCount: 0,
    pulledCount: 0,
    appliedCount: 0,
    deletedCount: 0,
    decryptFailedCount: 0,
    repushCount: 0,
    missingKeyQuarantinedCount: 0,
    corruptionQuarantinedCount: 0,
    resolvedQuarantineCount: 0,
    upgradeRequired: false,
  );
  int _listSeq = 0;
  int _taskSeq = 0;
  int _reminderSeq = 0;
  int _undoSeq = 0;
  int _accountSeq = 0;

  FakeLargeSeedSummary seedLargeDataset({
    int listCount = 10,
    int tasksPerList = 1000,
    int? todayStartMs,
  }) {
    _lists.clear();
    _tasks.clear();
    _reminders.clear();
    _undoEntries.clear();
    _pendingSyncMutations.clear();
    reorderCalls.clear();
    syncNowCalls = 0;
    _settings.clear();
    _settings[onboardingCompletedSettingKey] = '1';
    _accountSession = const AccountSessionStateDto(loggedIn: false);
    _syncStatus = const SyncStatusDto(
      loggedIn: false,
      running: false,
      pushedCount: 0,
      pushAckedCount: 0,
      pushSupersededCount: 0,
      pulledCount: 0,
      appliedCount: 0,
      deletedCount: 0,
      decryptFailedCount: 0,
      repushCount: 0,
      missingKeyQuarantinedCount: 0,
      corruptionQuarantinedCount: 0,
      resolvedQuarantineCount: 0,
      upgradeRequired: false,
    );
    _listSeq = listCount;
    _taskSeq = listCount * tasksPerList;
    _reminderSeq = 0;
    _undoSeq = 0;
    _accountSeq = 0;

    const rootTasksPerList = 700;
    const childTasksPerList = 220;
    final todayStart = todayStartMs ?? _localDayStartMs(DateTime.now());
    final tomorrowStart = todayStart + _fakeDayMs;
    var dueTaskCount = 0;
    var closedTaskCount = 0;

    for (var listIndex = 0; listIndex < listCount; listIndex += 1) {
      final now = _fakeTimestamp(listIndex);
      _lists.add(
        ListDto(
          id: 'large-list-$listIndex',
          name: 'Performance List ${listIndex + 1}',
          color: '',
          icon: '',
          sortOrder: 'a${listIndex.toString().padLeft(2, '0')}',
          isDefault: listIndex == 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    for (var listIndex = 0; listIndex < listCount; listIndex += 1) {
      final listId = 'large-list-$listIndex';
      final rootIds = <String>[];
      final childIds = <String>[];
      for (var taskIndex = 0; taskIndex < tasksPerList; taskIndex += 1) {
        final globalIndex = (listIndex * tasksPerList) + taskIndex;
        final taskId = 'large-task-$globalIndex';
        String? parentTaskId;
        if (taskIndex < rootTasksPerList) {
          rootIds.add(taskId);
        } else if (taskIndex < rootTasksPerList + childTasksPerList) {
          parentTaskId =
              rootIds[(taskIndex - rootTasksPerList) % rootIds.length];
          childIds.add(taskId);
        } else {
          parentTaskId =
              childIds[(taskIndex - rootTasksPerList - childTasksPerList) %
                  childIds.length];
        }
        final status = switch (globalIndex % 10) {
          0 => 'done',
          1 => 'wont_do',
          2 || 3 => 'in_progress',
          _ => 'todo',
        };
        final dueAt = switch (globalIndex % 6) {
          0 => null,
          1 => todayStart - _fakeDayMs,
          2 => todayStart + ((globalIndex % 12) * _fakeHourMs),
          3 => tomorrowStart + ((globalIndex % 8) * _fakeHourMs),
          4 => tomorrowStart + (7 * _fakeDayMs),
          _ => null,
        };
        if (dueAt != null) {
          dueTaskCount += 1;
        }
        final isClosed = status == 'done' || status == 'wont_do';
        final completedAt = isClosed
            ? globalIndex % 4 == 0
                  ? todayStart + ((globalIndex % 10) * _fakeTenMinuteMs)
                  : todayStart - (2 * _fakeDayMs)
            : null;
        if (isClosed) {
          closedTaskCount += 1;
        }
        final keyword = globalIndex % 17 == 0
            ? 'alpha'
            : globalIndex % 19 == 0
            ? '日本語'
            : 'routine';
        _tasks.add(
          TaskDto(
            id: taskId,
            listId: listId,
            parentTaskId: parentTaskId,
            title: 'Task ${globalIndex.toString().padLeft(5, '0')} $keyword',
            note: 'Seeded note ${globalIndex.toString().padLeft(5, '0')}',
            status: status,
            priority: globalIndex % 4,
            due: dueAt == null ? null : testDateOnlyDueFromMillis(dueAt),
            scheduledAt: dueAt == null ? null : dueAt - _fakeHourMs,
            estimatedMinutes: 15 + ((globalIndex % 6) * 10),
            sortOrder: 'a${taskIndex.toString().padLeft(4, '0')}',
            completedAt: completedAt,
            closedReason: status == 'wont_do' ? 'not_now' : null,
            createdAt: _fakeTimestamp(100 + globalIndex),
            updatedAt: _fakeTimestamp(200 + globalIndex),
          ),
        );
      }
    }

    return FakeLargeSeedSummary(
      listCount: listCount,
      taskCount: listCount * tasksPerList,
      dueTaskCount: dueTaskCount,
      closedTaskCount: closedTaskCount,
      defaultListId: _lists.first.id,
    );
  }

  @override
  Future<AccountSessionStateDto> getAccountSessionState() async {
    return _accountSession;
  }

  @override
  Future<AccountAuthResultDto> accountRegister({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw Exception('account request failed');
    }
    if (serverUrl != null && serverUrl.trim().isNotEmpty) {
      await setSyncServerUrl(serverUrl: serverUrl.trim());
    }
    final session = _newAccountSession(email.trim());
    _accountSession = session;
    _syncStatus = _copySyncStatus(_syncStatus, loggedIn: true);
    return AccountAuthResultDto(
      session: session,
      recoveryKey:
          'amber anchor apricot atlas bamboo beacon birch breeze cabin cedar cinder cobalt coral cotton dawn delta ember fern flint garden harbor hazel indigo juniper',
    );
  }

  @override
  Future<AccountAuthResultDto> accountLogin({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw Exception('account request failed');
    }
    if (serverUrl != null && serverUrl.trim().isNotEmpty) {
      await setSyncServerUrl(serverUrl: serverUrl.trim());
    }
    final session = _newAccountSession(email.trim());
    _accountSession = session;
    _syncStatus = _copySyncStatus(_syncStatus, loggedIn: true);
    return AccountAuthResultDto(session: session);
  }

  @override
  Future<void> accountLogout() async {
    _accountSession = const AccountSessionStateDto(loggedIn: false);
    _syncStatus = _copySyncStatus(_syncStatus, loggedIn: false);
  }

  @override
  Future<SyncStatusDto> getSyncStatus() async {
    return _syncStatus;
  }

  @override
  Future<SyncStatusDto> syncNow() async {
    syncNowCalls += 1;
    if (!_accountSession.loggedIn) {
      _syncStatus = _copySyncStatus(_syncStatus, loggedIn: false);
      return _syncStatus;
    }
    final syncMutations = List<void Function()>.of(_pendingSyncMutations);
    _pendingSyncMutations.clear();
    for (final mutation in syncMutations) {
      mutation();
    }
    _syncStatus = _copySyncStatus(
      _syncStatus,
      loggedIn: true,
      running: false,
      lastSuccessAt: _fakeTimestamp(_accountSeq + _taskSeq + _listSeq + 1),
      lastError: null,
    );
    return _syncStatus;
  }

  void addRemoteTaskForNextSync({
    required String listId,
    required String title,
    String? parentTaskId,
    int? dueAt,
    String note = '',
  }) {
    _pendingSyncMutations.add(() {
      final taskSeq = _taskSeq++;
      _tasks.add(
        TaskDto(
          id: 'remote-task-$taskSeq',
          listId: listId,
          parentTaskId: parentTaskId,
          title: title,
          note: note,
          status: 'todo',
          priority: 0,
          due: dueAt == null ? null : testDateOnlyDueFromMillis(dueAt),
          sortOrder: 'remote-$taskSeq',
          createdAt: _fakeTimestamp(3000 + taskSeq),
          updatedAt: _fakeTimestamp(3000 + taskSeq),
        ),
      );
    });
  }

  @override
  Future<String> getSyncServerUrl() async {
    return _settings[syncServerUrlSettingKey] ?? defaultSyncServerUrl;
  }

  @override
  Future<void> setSyncServerUrl({required String serverUrl}) async {
    _settings[syncServerUrlSettingKey] = serverUrl;
  }

  @override
  Future<String> getLocalTimeZone() async => 'UTC';

  @override
  Future<ListDto> createList({
    required String name,
    required String sortOrder,
  }) async {
    return _createList(name: name, sortOrder: sortOrder, isDefault: false);
  }

  Future<ListDto> createDefaultList({
    required String name,
    required String sortOrder,
  }) async {
    return _createList(name: name, sortOrder: sortOrder, isDefault: true);
  }

  Future<ListDto> _createList({
    required String name,
    required String sortOrder,
    required bool isDefault,
  }) async {
    final listSeq = _listSeq++;
    final now = _fakeTimestamp(listSeq);
    final list = ListDto(
      id: 'list-$listSeq',
      name: name,
      color: '',
      icon: '',
      sortOrder: sortOrder,
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
    );
    _lists.add(list);
    return list;
  }

  @override
  Future<List<ListDto>> getLists() async {
    final active = _lists
        .where((list) => list.archivedAt == null)
        .toList(growable: false);
    active.sort(_compareLists);
    return List.unmodifiable(active);
  }

  @override
  Future<List<ListDto>> getArchivedLists() async {
    final archived = _lists
        .where((list) => list.archivedAt != null)
        .toList(growable: false);
    archived.sort((a, b) {
      final archivedAt = b.archivedAt!.compareTo(a.archivedAt!);
      if (archivedAt != 0) {
        return archivedAt;
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return List.unmodifiable(archived);
  }

  @override
  Future<ListDto> renameList({
    required String listId,
    required String name,
  }) async {
    if (name.trim().isEmpty) {
      throw Exception('list name must not be empty');
    }
    final index = _lists.indexWhere((list) => list.id == listId);
    final list = _lists[index];
    final updated = ListDto(
      id: list.id,
      name: name,
      color: list.color,
      icon: list.icon,
      orgId: list.orgId,
      sortOrder: list.sortOrder,
      isDefault: list.isDefault,
      archivedAt: list.archivedAt,
      createdAt: list.createdAt,
      updatedAt: list.updatedAt + _fakeMinuteMs,
    );
    _lists[index] = updated;
    return updated;
  }

  @override
  Future<ListDto> archiveList({required String listId}) async {
    final index = _lists.indexWhere((list) => list.id == listId);
    final list = _lists[index];
    if (list.archivedAt == null && list.isDefault) {
      throw Exception('default list cannot be archived');
    }
    if (list.archivedAt != null) {
      return list;
    }
    final updatedAt = list.updatedAt + _fakeMinuteMs;
    final updated = _copyList(
      list,
      archivedAt: updatedAt,
      updatedAt: updatedAt,
    );
    _lists[index] = updated;
    return updated;
  }

  @override
  Future<ListDto> unarchiveList({required String listId}) async {
    final index = _lists.indexWhere((list) => list.id == listId);
    final list = _lists[index];
    if (list.archivedAt == null) {
      return list;
    }
    final updated = _copyList(
      list,
      clearArchivedAt: true,
      updatedAt: list.updatedAt + _fakeMinuteMs,
    );
    _lists[index] = updated;
    return updated;
  }

  @override
  Future<TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
    Object? due,
    String note = '',
    int priority = 0,
    int? scheduledAt,
    int? estimatedMinutes,
  }) async {
    if (priority < 0 || priority > 3) {
      throw Exception('task priority must be between 0 and 3');
    }
    if (estimatedMinutes != null &&
        (estimatedMinutes <= 0 || estimatedMinutes % 5 != 0)) {
      throw Exception('estimated minutes must be a positive multiple of 5');
    }
    final taskSeq = _taskSeq++;
    final siblings =
        _tasks
            .where(
              (task) =>
                  task.listId == listId && task.parentTaskId == parentTaskId,
            )
            .toList()
          ..sort(_compareTasks);
    final sortOrder = _fractionalIndexBetween(
      siblings.isEmpty ? null : siblings.last.sortOrder,
      null,
    );
    final task = TaskDto(
      id: 'task-$taskSeq',
      listId: listId,
      parentTaskId: parentTaskId,
      title: title,
      note: note,
      status: 'todo',
      priority: priority,
      due: _normalizeFakeDue(due),
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
      sortOrder: sortOrder,
      createdAt: _fakeTimestamp(100 + taskSeq),
      updatedAt: _fakeTimestamp(100 + taskSeq),
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<List<TaskDto>> getTasks({required String listId}) async {
    final tasks = _tasks.where((task) => task.listId == listId).toList();
    tasks.sort(_compareTasks);
    return tasks;
  }

  void setScheduledAtForTest({
    required String taskId,
    required int scheduledAt,
  }) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    _tasks[index] = _tasks[index]._copyWith(scheduledAt: scheduledAt);
  }

  @override
  Future<List<HomeTaskDto>> getHomeTasks({
    required int todayStartMs,
    required int tomorrowStartMs,
  }) async {
    final activeListById = {
      for (final list in _lists)
        if (list.archivedAt == null) list.id: list,
    };
    final homeTargetIds = <String>{};
    for (final task in _tasks) {
      final scheduledToday =
          task.scheduledAt != null &&
          task.scheduledAt! >= todayStartMs &&
          task.scheduledAt! < tomorrowStartMs;
      if ((task.due == null && !scheduledToday) ||
          !activeListById.containsKey(task.listId)) {
        continue;
      }
      if (task.status == 'todo' || task.status == 'in_progress') {
        homeTargetIds.add(task.id);
      } else if (task.status == 'done' || task.status == 'wont_do') {
        final completedAt = task.completedAt;
        if (completedAt != null &&
            completedAt >= todayStartMs &&
            completedAt < tomorrowStartMs) {
          homeTargetIds.add(task.id);
        }
      }
    }
    final childrenByParent = <String, List<TaskDto>>{};
    for (final task in _tasks) {
      final parentId = task.parentTaskId;
      if (parentId == null) {
        continue;
      }
      childrenByParent.putIfAbsent(parentId, () => <TaskDto>[]).add(task);
    }
    final homeScopeIds = <String>{};
    void includeSubtree(String taskId) {
      if (!homeScopeIds.add(taskId)) {
        return;
      }
      for (final child in childrenByParent[taskId] ?? const <TaskDto>[]) {
        includeSubtree(child.id);
      }
    }

    for (final taskId in homeTargetIds) {
      includeSubtree(taskId);
    }
    final taskById = {for (final task in _tasks) task.id: task};
    void includeAncestors(String taskId) {
      final task = taskById[taskId];
      if (task == null) {
        return;
      }
      final parentId = task.parentTaskId;
      if (parentId == null || !homeScopeIds.add(parentId)) {
        return;
      }
      includeAncestors(parentId);
    }

    for (final taskId in homeTargetIds) {
      includeAncestors(taskId);
    }

    final homeTasks = _tasks
        .where(
          (task) =>
              homeScopeIds.contains(task.id) &&
              activeListById.containsKey(task.listId),
        )
        .map(
          (task) => HomeTaskDto(
            task: task,
            listName: activeListById[task.listId]!.name,
            isHomeTarget: homeTargetIds.contains(task.id),
          ),
        )
        .toList();
    homeTasks.sort(_compareHomeTaskEntries);
    return List.unmodifiable(homeTasks);
  }

  @override
  Future<int> countTasksInList({required String listId}) async {
    return _tasks.where((task) => task.listId == listId).length;
  }

  @override
  Future<TaskDto> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    Object? due,
    int? scheduledAt,
    int? estimatedMinutes,
  }) async {
    if (title.trim().isEmpty) {
      throw Exception('task title must not be empty');
    }
    if (priority < 0 || priority > 3) {
      throw Exception('task priority must be between 0 and 3');
    }
    if (estimatedMinutes != null &&
        (estimatedMinutes <= 0 || estimatedMinutes % 5 != 0)) {
      throw Exception('estimated minutes must be a positive multiple of 5');
    }
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final task = _tasks[index];
    final updatedAt = task.updatedAt + _fakeMinuteMs;
    final updated = TaskDto(
      id: task.id,
      listId: task.listId,
      parentTaskId: task.parentTaskId,
      title: title,
      note: note,
      status: task.status,
      priority: priority,
      due: _normalizeFakeDue(due),
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
      sortOrder: task.sortOrder,
      completedAt: task.completedAt,
      closedReason: task.closedReason,
      deletedAt: task.deletedAt,
      assignee: task.assignee,
      createdAt: task.createdAt,
      updatedAt: updatedAt,
    );
    _tasks[index] = updated;
    _recordUndo(operationType: 'edit', before: task, after: updated);
    return updated;
  }

  @override
  Future<TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  }) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final before = _tasks[index];
    if (!_canTransition(before.status, status)) {
      throw Exception('invalid task status transition');
    }
    final updatedAt = before.updatedAt + _fakeMinuteMs;
    final isClosed = status == 'done' || status == 'wont_do';
    final completedAt = isClosed ? DateTime.now().millisecondsSinceEpoch : null;
    final updated = before._copyWith(
      status: status,
      completedAt: completedAt,
      closedReason: status == 'wont_do' ? closedReason : null,
      clearCompletedAt: !isClosed,
      clearClosedReason: status != 'wont_do',
      updatedAt: updatedAt,
    );
    _tasks[index] = updated;
    if (status == 'done' || status == 'wont_do') {
      _recordUndo(operationType: 'complete', before: before, after: updated);
    }
    return updated;
  }

  @override
  Future<int> countTaskDescendants({required String taskId}) async {
    return _descendantIds(taskId).length;
  }

  @override
  Future<void> deleteTask({required String taskId}) async {
    final ids = {taskId, ..._descendantIds(taskId)};
    _tasks.removeWhere((task) => ids.contains(task.id));
    _reminders.removeWhere((reminder) => ids.contains(reminder.taskId));
    _undoEntries.removeWhere((entry) => ids.contains(entry.taskId));
  }

  @override
  Future<void> deleteList({required String listId}) async {
    final list = _lists.singleWhere((candidate) => candidate.id == listId);
    if (list.isDefault) {
      throw Exception('default list cannot be deleted');
    }
    final taskIds = _tasks
        .where((task) => task.listId == listId)
        .map((task) => task.id)
        .toSet();
    _tasks.removeWhere((task) => task.listId == listId);
    _reminders.removeWhere((reminder) => taskIds.contains(reminder.taskId));
    _undoEntries.removeWhere((entry) => taskIds.contains(entry.taskId));
    _lists.removeWhere((candidate) => candidate.id == listId);
  }

  @override
  Future<TaskDto> reorderTask({
    required String taskId,
    String? previousTaskId,
    String? nextTaskId,
  }) async {
    reorderCalls.add(
      FakeReorderCall(
        taskId: taskId,
        previousTaskId: previousTaskId,
        nextTaskId: nextTaskId,
      ),
    );
    if (previousTaskId == taskId || nextTaskId == taskId) {
      throw Exception('task cannot be reordered relative to itself');
    }
    if (previousTaskId != null && previousTaskId == nextTaskId) {
      throw Exception('previous and next task must be different');
    }

    final index = _tasks.indexWhere((task) => task.id == taskId);
    final task = _tasks[index];
    final previous = previousTaskId == null
        ? null
        : _reorderBoundary(previousTaskId, task);
    final next = nextTaskId == null ? null : _reorderBoundary(nextTaskId, task);
    final updatedAt = task.updatedAt + _fakeMinuteMs;
    final updated = task._copyWith(
      sortOrder: _fractionalIndexBetween(previous?.sortOrder, next?.sortOrder),
      updatedAt: updatedAt,
    );
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<TaskUndoDto?> getLatestTaskUndo() async {
    final available = _undoEntries
        .where((entry) => !entry.consumed && entry.operationType != 'delete')
        .toList(growable: false);
    if (available.isEmpty) {
      return null;
    }
    available.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return available.first.dto;
  }

  @override
  Future<TaskDto> undoTaskOperation({required String undoId}) async {
    final entry = _undoEntries.singleWhere(
      (candidate) => candidate.id == undoId,
    );
    if (entry.consumed) {
      throw Exception('undo entry already used');
    }
    final index = _tasks.indexWhere((task) => task.id == entry.taskId);
    if (index < 0) {
      throw Exception('record not found');
    }
    final current = _tasks[index];
    if (current.updatedAt != entry.afterUpdatedAt ||
        current.deletedAt != entry.afterDeletedAt ||
        current.completedAt != entry.afterCompletedAt) {
      throw Exception('task changed after undo was created');
    }
    entry.consumed = true;
    _tasks[index] = entry.before;
    return entry.before;
  }

  @override
  Future<String?> getSetting({required String key}) async {
    return _settings[key];
  }

  @override
  Future<void> setSetting({required String key, required String value}) async {
    _settings[key] = value;
  }

  @override
  Future<ReminderDto> setTaskReminder({
    required String taskId,
    required int remindAt,
  }) async {
    if (!_tasks.any((task) => task.id == taskId)) {
      throw Exception('record not found');
    }
    _reminders.removeWhere((reminder) => reminder.taskId == taskId);
    final reminderSeq = _reminderSeq++;
    final reminder = ReminderDto(
      id: 'reminder-$reminderSeq',
      taskId: taskId,
      remindAt: remindAt,
      createdAt: _fakeTimestamp(2000 + reminderSeq),
    );
    _reminders.add(reminder);
    return reminder;
  }

  @override
  Future<List<ReminderDto>> clearTaskReminders({required String taskId}) async {
    final removed = _reminders
        .where((reminder) => reminder.taskId == taskId)
        .toList(growable: false);
    _reminders.removeWhere((reminder) => reminder.taskId == taskId);
    return List.unmodifiable(removed);
  }

  @override
  Future<List<ReminderDto>> getTaskReminders({required String taskId}) async {
    final reminders = _reminders
        .where((reminder) => reminder.taskId == taskId)
        .toList(growable: false);
    reminders.sort(_compareReminders);
    return List.unmodifiable(reminders);
  }

  @override
  Future<List<ReminderDto>> getTaskSubtreeReminders({
    required String taskId,
  }) async {
    final ids = {taskId, ..._descendantIds(taskId)};
    final reminders = _reminders
        .where((reminder) => ids.contains(reminder.taskId))
        .toList(growable: false);
    reminders.sort(_compareReminders);
    return List.unmodifiable(reminders);
  }

  @override
  Future<List<ReminderDto>> getListReminders({required String listId}) async {
    final taskIds = _tasks
        .where((task) => task.listId == listId)
        .map((task) => task.id)
        .toSet();
    final reminders = _reminders
        .where((reminder) => taskIds.contains(reminder.taskId))
        .toList(growable: false);
    reminders.sort(_compareReminders);
    return List.unmodifiable(reminders);
  }

  @override
  Future<List<ReminderDto>> listPendingReminders({required int nowMs}) async {
    final openTaskIds = _tasks
        .where((task) => task.status == 'todo' || task.status == 'in_progress')
        .map((task) => task.id)
        .toSet();
    final reminders = _reminders
        .where(
          (reminder) =>
              openTaskIds.contains(reminder.taskId) &&
              _effectiveReminderAt(reminder) > nowMs,
        )
        .toList(growable: false);
    reminders.sort(_compareReminders);
    return List.unmodifiable(reminders);
  }

  @override
  Future<ReminderDto> snoozeReminder({
    required String reminderId,
    required int snoozedUntil,
  }) async {
    final index = _reminders.indexWhere(
      (reminder) => reminder.id == reminderId,
    );
    if (index < 0) {
      throw Exception('record not found');
    }
    final current = _reminders[index];
    final updated = ReminderDto(
      id: current.id,
      taskId: current.taskId,
      remindAt: current.remindAt,
      snoozedUntil: snoozedUntil,
      createdAt: current.createdAt,
    );
    _reminders[index] = updated;
    return updated;
  }

  TaskDto _reorderBoundary(String boundaryId, TaskDto task) {
    final boundary = _tasks.singleWhere(
      (candidate) => candidate.id == boundaryId,
    );
    if (boundary.listId != task.listId) {
      throw Exception('reorder boundary belongs to a different list');
    }
    if (boundary.parentTaskId != task.parentTaskId) {
      throw Exception('reorder boundary belongs to a different parent');
    }
    return boundary;
  }

  void _recordUndo({
    required String operationType,
    required TaskDto before,
    required TaskDto after,
  }) {
    final undoSeq = _undoSeq++;
    final id = 'undo-$undoSeq';
    final createdAt = _fakeTimestamp(1000 + undoSeq);
    _undoEntries.add(
      FakeTaskUndoEntry(
        id: id,
        operationType: operationType,
        taskId: before.id,
        before: before,
        afterUpdatedAt: after.updatedAt,
        afterDeletedAt: after.deletedAt,
        afterCompletedAt: after.completedAt,
        createdAt: createdAt,
        dto: TaskUndoDto(
          id: id,
          operationType: operationType,
          taskId: before.id,
          listId: before.listId,
          taskTitle: before.title,
          createdAt: createdAt,
        ),
      ),
    );
  }

  Set<String> _descendantIds(String taskId) {
    final descendants = <String>{};
    var frontier = <String>{taskId};
    while (frontier.isNotEmpty) {
      final next = _tasks
          .where((task) => frontier.contains(task.parentTaskId))
          .map((task) => task.id)
          .where(descendants.add)
          .toSet();
      frontier = next;
    }
    return descendants;
  }

  AccountSessionStateDto _newAccountSession(String email) {
    final accountSeq = _accountSeq++;
    return AccountSessionStateDto(
      loggedIn: true,
      email: email,
      userId: 'user-$accountSeq',
      tenantId: 'tenant-$accountSeq',
      deviceId: 'device-$accountSeq',
    );
  }
}

class FakeLargeSeedSummary {
  const FakeLargeSeedSummary({
    required this.listCount,
    required this.taskCount,
    required this.dueTaskCount,
    required this.closedTaskCount,
    required this.defaultListId,
  });

  final int listCount;
  final int taskCount;
  final int dueTaskCount;
  final int closedTaskCount;
  final String defaultListId;
}

bool _canTransition(String current, String next) {
  if (current == next) {
    return false;
  }
  return switch ((current, next)) {
    ('todo', 'in_progress') ||
    ('todo', 'done') ||
    ('todo', 'wont_do') ||
    ('in_progress', 'todo') ||
    ('in_progress', 'done') ||
    ('in_progress', 'wont_do') ||
    ('done', 'todo') ||
    ('wont_do', 'todo') => true,
    _ => false,
  };
}

final int _fakeClockBaseMs = DateTime.utc(2026, 7, 1, 9).millisecondsSinceEpoch;

const int _fakeMinuteMs = Duration.millisecondsPerMinute;
const int _fakeTenMinuteMs = 10 * Duration.millisecondsPerMinute;
const int _fakeHourMs = Duration.millisecondsPerHour;
const int _fakeDayMs = Duration.millisecondsPerDay;

int _fakeTimestamp(int sequence) =>
    _fakeClockBaseMs + (sequence * _fakeMinuteMs);

int _localDayStartMs(DateTime dateTime) {
  final local = dateTime.toLocal();
  return DateTime(local.year, local.month, local.day).millisecondsSinceEpoch;
}

/// A recorded undo entry for [FakeBridgeService].
///
/// Public so it can be referenced from other test support code if needed;
/// mirrors the shape of the real undo log without touching storage.
class FakeTaskUndoEntry {
  FakeTaskUndoEntry({
    required this.id,
    required this.operationType,
    required this.taskId,
    required this.before,
    required this.afterUpdatedAt,
    required this.afterDeletedAt,
    required this.afterCompletedAt,
    required this.createdAt,
    required this.dto,
  });

  final String id;
  final String operationType;
  final String taskId;
  final TaskDto before;
  final int afterUpdatedAt;
  final int? afterDeletedAt;
  final int? afterCompletedAt;
  final int createdAt;
  final TaskUndoDto dto;
  bool consumed = false;
}

class FakeReorderCall {
  const FakeReorderCall({
    required this.taskId,
    required this.previousTaskId,
    required this.nextTaskId,
  });

  final String taskId;
  final String? previousTaskId;
  final String? nextTaskId;
}

extension _TaskDtoCopy on TaskDto {
  TaskDto _copyWith({
    String? title,
    String? note,
    String? status,
    int? priority,
    Object? due = _unchangedTaskDue,
    int? completedAt,
    String? closedReason,
    int? deletedAt,
    int? scheduledAt,
    String? sortOrder,
    int? updatedAt,
    bool clearCompletedAt = false,
    bool clearClosedReason = false,
  }) {
    return TaskDto(
      id: id,
      listId: listId,
      parentTaskId: parentTaskId,
      title: title ?? this.title,
      note: note ?? this.note,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      due: identical(due, _unchangedTaskDue) ? this.due : due as TaskDueDto?,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      estimatedMinutes: estimatedMinutes,
      sortOrder: sortOrder ?? this.sortOrder,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      closedReason: clearClosedReason
          ? null
          : closedReason ?? this.closedReason,
      deletedAt: deletedAt ?? this.deletedAt,
      assignee: assignee,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

int _compareTasks(TaskDto a, TaskDto b) {
  final sortOrder = a.sortOrder.compareTo(b.sortOrder);
  if (sortOrder != 0) {
    return sortOrder;
  }
  return a.id.compareTo(b.id);
}

int _compareHomeTaskEntries(HomeTaskDto a, HomeTaskDto b) {
  final due = compareTaskDue(a.task.due, b.task.due);
  if (due != 0) {
    return due;
  }
  return _compareTasks(a.task, b.task);
}

const _unchangedTaskDue = Object();

TaskDueDto? _normalizeFakeDue(Object? value) => switch (value) {
  null => null,
  TaskDueDto due => due,
  TaskDueInput due => taskDueDto(due),
  _ => throw ArgumentError.value(value, 'due'),
};

int _compareReminders(ReminderDto a, ReminderDto b) {
  final effectiveAt = _effectiveReminderAt(
    a,
  ).compareTo(_effectiveReminderAt(b));
  if (effectiveAt != 0) {
    return effectiveAt;
  }
  final createdAt = a.createdAt.compareTo(b.createdAt);
  if (createdAt != 0) {
    return createdAt;
  }
  return a.id.compareTo(b.id);
}

int _effectiveReminderAt(ReminderDto reminder) =>
    reminder.snoozedUntil ?? reminder.remindAt;

int _compareLists(ListDto a, ListDto b) {
  final sortOrder = a.sortOrder.compareTo(b.sortOrder);
  if (sortOrder != 0) {
    return sortOrder;
  }
  return a.id.compareTo(b.id);
}

ListDto _copyList(
  ListDto list, {
  String? name,
  int? archivedAt,
  bool clearArchivedAt = false,
  int? updatedAt,
}) {
  return ListDto(
    id: list.id,
    name: name ?? list.name,
    color: list.color,
    icon: list.icon,
    orgId: list.orgId,
    sortOrder: list.sortOrder,
    isDefault: list.isDefault,
    archivedAt: clearArchivedAt ? null : archivedAt ?? list.archivedAt,
    createdAt: list.createdAt,
    updatedAt: updatedAt ?? list.updatedAt,
  );
}

SyncStatusDto _copySyncStatus(
  SyncStatusDto status, {
  bool? loggedIn,
  bool? running,
  int? lastSuccessAt,
  int? lastFailureAt,
  String? lastError,
}) {
  return SyncStatusDto(
    loggedIn: loggedIn ?? status.loggedIn,
    running: running ?? status.running,
    lastSuccessAt: lastSuccessAt ?? status.lastSuccessAt,
    lastFailureAt: lastFailureAt ?? status.lastFailureAt,
    lastError: lastError,
    pushedCount: status.pushedCount,
    pushAckedCount: status.pushAckedCount,
    pushSupersededCount: status.pushSupersededCount,
    pulledCount: status.pulledCount,
    appliedCount: status.appliedCount,
    deletedCount: status.deletedCount,
    decryptFailedCount: status.decryptFailedCount,
    repushCount: status.repushCount,
    missingKeyQuarantinedCount: status.missingKeyQuarantinedCount,
    corruptionQuarantinedCount: status.corruptionQuarantinedCount,
    resolvedQuarantineCount: status.resolvedQuarantineCount,
    upgradeRequired: status.upgradeRequired,
  );
}

const _sortAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

String _fractionalIndexBetween(String? previous, String? next) {
  if (previous != null) {
    _validateSortOrder(previous);
  }
  if (next != null) {
    _validateSortOrder(next);
  }
  if (previous != null && next != null && previous.compareTo(next) >= 0) {
    throw Exception('invalid sort order boundary');
  }

  final buffer = StringBuffer();
  var index = 0;
  while (true) {
    final previousDigit = _digitAt(previous, index, isPrevious: true);
    final nextDigit = _digitAt(next, index, isPrevious: false);
    if (nextDigit - previousDigit > 1) {
      return '${buffer.toString()}'
          '${_sortAlphabet[(previousDigit + ((nextDigit - previousDigit) ~/ 2))]}';
    }
    if (previousDigit < 0) {
      if (next != null && index + 1 < next.length) {
        return '${buffer.toString()}${_sortAlphabet[nextDigit]}';
      }
      throw Exception('sort order space is exhausted');
    }
    buffer.write(_sortAlphabet[previousDigit]);
    index += 1;
  }
}

void _validateSortOrder(String value) {
  if (value.isEmpty ||
      value.split('').any((char) => !_sortAlphabet.contains(char))) {
    throw Exception('invalid sort order');
  }
}

int _digitAt(String? value, int index, {required bool isPrevious}) {
  if (value == null) {
    return isPrevious ? -1 : _sortAlphabet.length;
  }
  if (index >= value.length) {
    return isPrevious ? -1 : _sortAlphabet.length;
  }
  return _sortAlphabet.indexOf(value[index]);
}
