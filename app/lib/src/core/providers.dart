import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/core/task_tree.dart';
import 'package:todori/src/core/task_due.dart';
import 'package:todori/src/notifications/reminder_notifications.dart';
import 'package:todori/src/rust/api.dart'
    show
        AccountAuthResultDto,
        AccountSessionStateDto,
        HomeTaskDto,
        ListDto,
        ReminderDto,
        SyncStatusDto,
        TaskDto,
        TaskDueDto,
        TaskUndoDto;

/// The [BridgeService] used by the app.
///
/// Defaults to [FrbBridgeService] (the real native bridge). Widget tests
/// override this with an in-memory fake via
/// `ProviderScope(overrides: [bridgeServiceProvider.overrideWithValue(fake)])`
/// so no test depends on the native Rust library or `initCore`.
final bridgeServiceProvider = Provider<BridgeService>(
  (ref) => const FrbBridgeService(),
);

const uiModeSettingKey = 'ui_mode';
const onboardingCompletedSettingKey = 'onboarding_completed';
const syncServerUrlSettingKey = 'sync_server_url';
const defaultSyncServerUrl = 'http://localhost:3000';
const defaultUiMode = 'simple';
const simpleUiMode = 'simple';
const advancedUiMode = 'advanced';
const _supportedUiModes = {simpleUiMode, advancedUiMode};

/// Thin typed entry point for app settings stored in the encrypted local DB.
///
/// The generic key/value methods are kept for future notification, theme, and
/// account settings. Feature-specific helpers own defaults and validation.
class SettingsRepository {
  SettingsRepository(this._bridge);

  final BridgeService _bridge;

  Future<String?> getSetting(String key) {
    return _bridge.getSetting(key: key);
  }

  Future<void> setSetting(String key, String value) {
    return _bridge.setSetting(key: key, value: value);
  }

  Future<String> getUiMode() async {
    final persisted = await getSetting(uiModeSettingKey);
    if (persisted == null || !_supportedUiModes.contains(persisted)) {
      return defaultUiMode;
    }
    return persisted;
  }

  Future<void> setUiMode(String uiMode) {
    if (!_supportedUiModes.contains(uiMode)) {
      throw ArgumentError.value(uiMode, 'uiMode', 'unsupported UI mode');
    }
    return setSetting(uiModeSettingKey, uiMode);
  }
}

class SyncServerUrlNotifier extends AsyncNotifier<String> {
  @override
  FutureOr<String> build() {
    return ref.watch(bridgeServiceProvider).getSyncServerUrl();
  }

  Future<void> setServerUrl(String serverUrl) async {
    await ref
        .read(bridgeServiceProvider)
        .setSyncServerUrl(serverUrl: serverUrl);
    ref.invalidateSelf();
  }
}

final syncServerUrlProvider =
    AsyncNotifierProvider<SyncServerUrlNotifier, String>(
      SyncServerUrlNotifier.new,
    );

class AccountNotifier extends AsyncNotifier<AccountSessionStateDto> {
  @override
  FutureOr<AccountSessionStateDto> build() {
    return ref.watch(bridgeServiceProvider).getAccountSessionState();
  }

  Future<AccountAuthResultDto> register({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  }) async {
    final result = await ref
        .read(bridgeServiceProvider)
        .accountRegister(
          email: email,
          password: password,
          serverUrl: serverUrl,
          deviceName: deviceName,
        );
    state = AsyncData(result.session);
    ref.invalidate(syncServerUrlProvider);
    return result;
  }

  Future<AccountAuthResultDto> login({
    required String email,
    required String password,
    String? serverUrl,
    String? deviceName,
  }) async {
    final result = await ref
        .read(bridgeServiceProvider)
        .accountLogin(
          email: email,
          password: password,
          serverUrl: serverUrl,
          deviceName: deviceName,
        );
    state = AsyncData(result.session);
    ref.invalidate(syncServerUrlProvider);
    return result;
  }

  Future<void> logout() async {
    await ref.read(bridgeServiceProvider).accountLogout();
    ref.invalidateSelf();
  }
}

final accountProvider =
    AsyncNotifierProvider<AccountNotifier, AccountSessionStateDto>(
      AccountNotifier.new,
    );

class SyncStatusNotifier extends AsyncNotifier<SyncStatusDto> {
  Timer? _pollTimer;

  @override
  FutureOr<SyncStatusDto> build() async {
    ref.onDispose(() => _pollTimer?.cancel());
    final account = await ref.watch(accountProvider.future);
    final bridge = ref.watch(bridgeServiceProvider);
    final status = await bridge.getSyncStatus();
    if (account.loggedIn && status.loggedIn) {
      _startPolling();
      unawaited(syncNow());
    }
    return status;
  }

  Future<void> syncNow() async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(_copySyncStatus(current, running: true));
    }
    final status = await ref.read(bridgeServiceProvider).syncNow();
    state = AsyncData(status);
    ref.invalidate(listsProvider);
    ref.invalidate(archivedListsProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(homeTasksProvider);
    ref.invalidate(latestTaskUndoProvider);
    ref.invalidate(taskRemindersProvider);
  }

  Future<void> syncOnResume() async {
    final status = state.value;
    if (status == null || !status.loggedIn || status.running) {
      return;
    }
    await syncNow();
  }

  void _startPolling() {
    if (_pollTimer != null) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final status = state.value;
      if (status != null && status.loggedIn && !status.running) {
        unawaited(syncNow());
      }
    });
  }
}

final syncStatusProvider =
    AsyncNotifierProvider<SyncStatusNotifier, SyncStatusDto>(
      SyncStatusNotifier.new,
    );

SyncStatusDto _copySyncStatus(SyncStatusDto status, {bool? running}) {
  return SyncStatusDto(
    loggedIn: status.loggedIn,
    running: running ?? status.running,
    lastSuccessAt: status.lastSuccessAt,
    lastFailureAt: status.lastFailureAt,
    lastError: status.lastError,
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

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(bridgeServiceProvider)),
);

final reminderNotificationGatewayProvider =
    Provider<ReminderNotificationGateway>(
      (ref) => FlutterLocalReminderNotificationGateway(),
    );

final reminderNotificationServiceProvider =
    Provider<ReminderNotificationService>(
      (ref) => ReminderNotificationService(
        bridge: ref.watch(bridgeServiceProvider),
        gateway: ref.watch(reminderNotificationGatewayProvider),
      ),
    );

/// Provides the reserved F-01 UI mode setting.
///
/// Phase 1 exposes only the persistence port. Selection/onboarding UI is a
/// Phase 3 concern.
class UiModeNotifier extends AsyncNotifier<String> {
  @override
  FutureOr<String> build() {
    return ref.watch(settingsRepositoryProvider).getUiMode();
  }

  Future<void> setUiMode(String uiMode) async {
    await ref.read(settingsRepositoryProvider).setUiMode(uiMode);
    ref.invalidateSelf();
  }
}

final uiModeProvider = AsyncNotifierProvider<UiModeNotifier, String>(
  UiModeNotifier.new,
);

/// Gates the one-time welcome experience before the app starts its ordinary
/// Home and sync providers. The flag is device-local and remains inside the
/// encrypted settings table; it is intentionally not synchronized.
class OnboardingStatusNotifier extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() async {
    final value = await ref
        .watch(settingsRepositoryProvider)
        .getSetting(onboardingCompletedSettingKey);
    return value == '1';
  }

  Future<void> complete() async {
    await ref
        .read(settingsRepositoryProvider)
        .setSetting(onboardingCompletedSettingKey, '1');
    state = const AsyncData(true);
  }
}

final onboardingStatusProvider =
    AsyncNotifierProvider<OnboardingStatusNotifier, bool>(
      OnboardingStatusNotifier.new,
    );

/// Generates a placeholder, monotonically-appending sort order string (e.g.
/// `a0`, `a1`, `a2`, ...) for newly created lists in this UI skeleton.
///
/// This is intentionally NOT a real fractional-index implementation: it
/// cannot express "insert between two existing items" or rebalance existing
/// values. Task sort orders are generated by the Rust/domain layer.
String nextSortOrder(int existingItemCount) => 'a$existingItemCount';

/// Manages the list of [ListDto]s shown on the lists screen.
///
/// Invalidate strategy: [createList] performs the bridge call first, then
/// calls `ref.invalidateSelf()`, which re-runs [build] and re-fetches
/// `getLists()`. Any widget that does `ref.watch(listsProvider)` is rebuilt
/// automatically with the refreshed `AsyncValue`.
class ListsNotifier extends AsyncNotifier<List<ListDto>> {
  @override
  FutureOr<List<ListDto>> build() {
    return ref.watch(bridgeServiceProvider).getLists();
  }

  /// Creates a new list named `name` and refreshes [listsProvider].
  Future<void> createList(String name) async {
    final bridge = ref.read(bridgeServiceProvider);
    final sortOrder = nextSortOrder(state.value?.length ?? 0);
    await bridge.createList(name: name, sortOrder: sortOrder);
    ref.invalidateSelf();
  }

  /// Renames `listId` and refreshes [listsProvider].
  Future<void> renameList(String listId, String name) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.renameList(listId: listId, name: name);
    ref.invalidateSelf();
    ref.invalidate(archivedListsProvider);
  }

  /// Archives `listId` and refreshes active and archived list collections.
  Future<void> archiveList(String listId) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.archiveList(listId: listId);
    ref.invalidateSelf();
    ref.invalidate(archivedListsProvider);
  }

  Future<int> countTasks(String listId) {
    return ref.read(bridgeServiceProvider).countTasksInList(listId: listId);
  }

  /// Permanently deletes `listId` and refreshes list collections.
  Future<void> deleteList(String listId) async {
    final bridge = ref.read(bridgeServiceProvider);
    final reminders = await bridge.getListReminders(listId: listId);
    await bridge.deleteList(listId: listId);
    await ref
        .read(reminderNotificationServiceProvider)
        .cancelReminders(reminders);
    ref.invalidateSelf();
    ref.invalidate(archivedListsProvider);
  }
}

final listsProvider = AsyncNotifierProvider<ListsNotifier, List<ListDto>>(
  ListsNotifier.new,
);

/// Manages archived lists shown in the collapsed archive section.
class ArchivedListsNotifier extends AsyncNotifier<List<ListDto>> {
  @override
  FutureOr<List<ListDto>> build() {
    return ref.watch(bridgeServiceProvider).getArchivedLists();
  }

  /// Restores `listId` and refreshes archived and active list collections.
  Future<void> unarchiveList(String listId) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.unarchiveList(listId: listId);
    ref.invalidateSelf();
    ref.invalidate(listsProvider);
  }
}

final archivedListsProvider =
    AsyncNotifierProvider<ArchivedListsNotifier, List<ListDto>>(
      ArchivedListsNotifier.new,
    );

/// Keeps the selected task display order in memory for the current app
/// session. Phase 1 intentionally does not persist this value to storage.
class TaskSortModeNotifier extends Notifier<TaskSortMode> {
  TaskSortModeNotifier(this.listId);

  final String listId;

  @override
  TaskSortMode build() {
    return TaskSortMode.manual;
  }

  void setMode(TaskSortMode mode) {
    state = mode;
  }
}

final taskSortModeProvider =
    NotifierProvider.family<TaskSortModeNotifier, TaskSortMode, String>(
      TaskSortModeNotifier.new,
    );

DateTime localDayStart(DateTime dateTime) {
  final local = dateTime.toLocal();
  return DateTime(local.year, local.month, local.day);
}

({int startMs, int endMs}) todayLocalRangeMs({DateTime? now}) {
  final start = localDayStart(now ?? DateTime.now());
  return (
    startMs: start.millisecondsSinceEpoch,
    endMs: start.add(const Duration(days: 1)).millisecondsSinceEpoch,
  );
}

({int todayStartMs, int tomorrowStartMs, int dayAfterTomorrowStartMs})
homeLocalRangesMs({DateTime? now}) {
  final todayStart = localDayStart(now ?? DateTime.now());
  final tomorrowStart = todayStart.add(const Duration(days: 1));
  return (
    todayStartMs: todayStart.millisecondsSinceEpoch,
    tomorrowStartMs: tomorrowStart.millisecondsSinceEpoch,
    dayAfterTomorrowStartMs: tomorrowStart
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch,
  );
}

/// Manages the tasks of a single list, keyed by `listId`.
///
/// Invalidate strategy: [createTask], [updateTask], [setStatus] and [deleteTask] each
/// perform their bridge call first, then call `ref.invalidateSelf()`, which
/// re-runs [build] for this `listId` only (other lists' [TasksNotifier]
/// instances are untouched). [taskDetailProvider] derives its value from
/// this provider via `ref.watch`, so it is refreshed transitively whenever
/// this provider is invalidated -- no separate invalidate call is needed for
/// the detail screen.
class TasksNotifier extends AsyncNotifier<List<TaskDto>> {
  TasksNotifier(this.listId);

  final String listId;

  @override
  FutureOr<List<TaskDto>> build() {
    return ref.watch(bridgeServiceProvider).getTasks(listId: listId);
  }

  /// Creates a new task titled `title` in this list and refreshes the task
  /// list. When [parentTaskId] is provided, the new task is created as a
  /// subtask of that parent. The Rust/domain layer assigns the task sort order
  /// within the target sibling group.
  Future<void> createTask(
    String title, {
    String? parentTaskId,
    TaskDueDto? due,
    String note = '',
    int priority = 0,
    int? scheduledAt,
    int? estimatedMinutes,
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.createTask(
      listId: listId,
      title: title,
      parentTaskId: parentTaskId,
      due: due == null ? null : taskDueInput(due),
      note: note,
      priority: priority,
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
    );
    ref.invalidate(homeTasksProvider);
    ref.invalidateSelf();
  }

  /// Updates editable task fields and refreshes the task list.
  Future<void> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    required TaskDueDto? due,
    required int? scheduledAt,
    required int? estimatedMinutes,
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.updateTask(
      taskId: taskId,
      title: title,
      note: note,
      priority: priority,
      due: due == null ? null : taskDueInput(due),
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
    );
    ref.invalidate(latestTaskUndoProvider);
    ref.invalidate(homeTasksProvider);
    ref.invalidateSelf();
  }

  Future<void> updateDue(TaskDto task, TaskDueDto? due) async {
    await updateTask(
      taskId: task.id,
      title: task.title,
      note: task.note,
      priority: task.priority,
      due: due,
      scheduledAt: task.scheduledAt,
      estimatedMinutes: task.estimatedMinutes,
    );
    ref.invalidate(homeTasksProvider);
  }

  /// Transitions `taskId` to `status` and refreshes the task list.
  Future<void> setStatus(
    String taskId,
    String status, {
    String? closedReason,
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    final reminders = status == 'done' || status == 'wont_do'
        ? await bridge.getTaskReminders(taskId: taskId)
        : const <ReminderDto>[];
    await bridge.setTaskStatus(
      taskId: taskId,
      status: status,
      closedReason: closedReason,
    );
    if (status == 'done' || status == 'wont_do') {
      await ref
          .read(reminderNotificationServiceProvider)
          .cancelReminders(reminders);
      ref.invalidate(latestTaskUndoProvider);
      ref.invalidate(taskRemindersProvider(taskId));
    }
    ref.invalidate(homeTasksProvider);
    ref.invalidateSelf();
  }

  Future<int> countDescendants(String taskId) {
    return ref.read(bridgeServiceProvider).countTaskDescendants(taskId: taskId);
  }

  /// Permanently deletes `taskId` and its descendants, then refreshes the list.
  Future<void> deleteTask(String taskId) async {
    final bridge = ref.read(bridgeServiceProvider);
    final reminders = await bridge.getTaskSubtreeReminders(taskId: taskId);
    await bridge.deleteTask(taskId: taskId);
    await ref
        .read(reminderNotificationServiceProvider)
        .cancelReminders(reminders);
    ref.invalidate(taskRemindersProvider(taskId));
    ref.invalidate(homeTasksProvider);
    ref.invalidateSelf();
  }

  /// Moves `taskId` between sibling boundaries and refreshes the task list.
  Future<void> reorderTask({
    required String taskId,
    required String? previousTaskId,
    required String? nextTaskId,
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.reorderTask(
      taskId: taskId,
      previousTaskId: previousTaskId,
      nextTaskId: nextTaskId,
    );
    ref.invalidateSelf();
  }
}

final tasksProvider =
    AsyncNotifierProvider.family<TasksNotifier, List<TaskDto>, String>(
      TasksNotifier.new,
    );

/// Manages the cross-list Home smart view.
class HomeTasksNotifier extends AsyncNotifier<List<HomeTaskDto>> {
  @override
  FutureOr<List<HomeTaskDto>> build() {
    final range = homeLocalRangesMs();
    return ref
        .watch(bridgeServiceProvider)
        .getHomeTasks(
          todayStartMs: range.todayStartMs,
          tomorrowStartMs: range.tomorrowStartMs,
        );
  }

  Future<void> createTask({
    required String listId,
    required String title,
    required TaskDueDto? due,
    required int priority,
    required int? scheduledAt,
    required int? estimatedMinutes,
    String note = '',
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.createTask(
      listId: listId,
      title: title,
      due: due == null ? null : taskDueInput(due),
      note: note,
      priority: priority,
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
    );
    ref.invalidate(tasksProvider(listId));
    ref.invalidateSelf();
  }

  Future<void> setStatus(
    String taskId,
    String status, {
    String? closedReason,
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    final reminders = status == 'done' || status == 'wont_do'
        ? await bridge.getTaskReminders(taskId: taskId)
        : const <ReminderDto>[];
    final updated = await bridge.setTaskStatus(
      taskId: taskId,
      status: status,
      closedReason: closedReason,
    );
    if (status == 'done' || status == 'wont_do') {
      await ref
          .read(reminderNotificationServiceProvider)
          .cancelReminders(reminders);
      ref.invalidate(latestTaskUndoProvider);
      ref.invalidate(taskRemindersProvider(taskId));
    }
    ref.invalidate(tasksProvider(updated.listId));
    ref.invalidateSelf();
  }

  Future<void> updateDue(TaskDto task, TaskDueDto? due) async {
    final bridge = ref.read(bridgeServiceProvider);
    final updated = await bridge.updateTask(
      taskId: task.id,
      title: task.title,
      note: task.note,
      priority: task.priority,
      due: due == null ? null : taskDueInput(due),
      scheduledAt: task.scheduledAt,
      estimatedMinutes: task.estimatedMinutes,
    );
    ref.invalidate(latestTaskUndoProvider);
    ref.invalidate(tasksProvider(updated.listId));
    ref.invalidateSelf();
  }
}

final homeTasksProvider =
    AsyncNotifierProvider<HomeTasksNotifier, List<HomeTaskDto>>(
      HomeTasksNotifier.new,
    );

/// Identifies a single task for [taskDetailProvider]: the containing list id
/// plus the task id.
typedef TaskDetailArgs = ({String listId, String taskId});

/// Task detail lookup policy (M2-03): there is no dedicated "get task by
/// id" bridge API exposed yet, so the detail screen derives its data by
/// watching [tasksProvider] for the task's list and finding the matching
/// task client-side. This keeps a single cache/source of truth for tasks
/// (avoids a second, possibly stale, copy of task data) and avoids an extra
/// round trip to the bridge. If a dedicated get-task-by-id bridge call is
/// added later, this provider's body can be swapped to call it directly
/// without changing the screen that consumes it.
final taskDetailProvider =
    Provider.family<AsyncValue<TaskDto?>, TaskDetailArgs>((ref, args) {
      final tasksAsync = ref.watch(tasksProvider(args.listId));
      return tasksAsync.whenData((tasks) {
        for (final task in tasks) {
          if (task.id == args.taskId) {
            return task;
          }
        }
        return null;
      });
    });

/// Manages the latest task undo entry and applies undo through the bridge.
class LatestTaskUndoNotifier extends AsyncNotifier<TaskUndoDto?> {
  @override
  FutureOr<TaskUndoDto?> build() {
    return ref.watch(bridgeServiceProvider).getLatestTaskUndo();
  }

  Future<TaskDto> undo(String undoId) async {
    final restored = await ref
        .read(bridgeServiceProvider)
        .undoTaskOperation(undoId: undoId);
    ref.invalidate(tasksProvider(restored.listId));
    ref.invalidate(homeTasksProvider);
    ref.invalidateSelf();
    await ref.read(tasksProvider(restored.listId).future);
    return restored;
  }
}

final latestTaskUndoProvider =
    AsyncNotifierProvider<LatestTaskUndoNotifier, TaskUndoDto?>(
      LatestTaskUndoNotifier.new,
    );

/// Manages reminders attached to a single task.
class TaskRemindersNotifier extends AsyncNotifier<List<ReminderDto>> {
  TaskRemindersNotifier(this.taskId);

  final String taskId;

  @override
  FutureOr<List<ReminderDto>> build() {
    return ref.watch(bridgeServiceProvider).getTaskReminders(taskId: taskId);
  }

  Future<ReminderDto> setReminder(int remindAt) async {
    final reminder = await ref
        .read(bridgeServiceProvider)
        .setTaskReminder(taskId: taskId, remindAt: remindAt);
    ref.invalidateSelf();
    return reminder;
  }

  Future<List<ReminderDto>> clearReminders() async {
    final reminders = await ref
        .read(bridgeServiceProvider)
        .clearTaskReminders(taskId: taskId);
    await ref
        .read(reminderNotificationServiceProvider)
        .cancelReminders(reminders);
    ref.invalidateSelf();
    return reminders;
  }
}

final taskRemindersProvider =
    AsyncNotifierProvider.family<
      TaskRemindersNotifier,
      List<ReminderDto>,
      String
    >(TaskRemindersNotifier.new);
