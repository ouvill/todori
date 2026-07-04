import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/rust/api.dart' show ListDto, TaskDto;

/// The [BridgeService] used by the app.
///
/// Defaults to [FrbBridgeService] (the real native bridge). Widget tests
/// override this with an in-memory fake via
/// `ProviderScope(overrides: [bridgeServiceProvider.overrideWithValue(fake)])`
/// so no test depends on the native Rust library or `initCore`.
final bridgeServiceProvider = Provider<BridgeService>(
  (ref) => const FrbBridgeService(),
);

/// Generates a placeholder, monotonically-appending sort order string (e.g.
/// `a0`, `a1`, `a2`, ...) for newly created lists/tasks in this UI skeleton
/// (M2-03).
///
/// This is intentionally NOT a real fractional-index implementation: it
/// cannot express "insert between two existing items" or rebalance existing
/// values. Fractional index generation (for drag-and-drop reordering) is
/// implemented in M3; this helper only needs to keep newly appended items
/// ordered after existing ones for the skeleton screens.
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
}

final listsProvider = AsyncNotifierProvider<ListsNotifier, List<ListDto>>(
  ListsNotifier.new,
);

/// Manages the active (non-trashed) tasks of a single list, keyed by
/// `listId`.
///
/// Invalidate strategy: [createTask], [updateTask], [setStatus] and [trashTask] each
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
  /// list.
  Future<void> createTask(String title) async {
    final bridge = ref.read(bridgeServiceProvider);
    final sortOrder = nextSortOrder(state.value?.length ?? 0);
    await bridge.createTask(listId: listId, title: title, sortOrder: sortOrder);
    ref.invalidateSelf();
  }

  /// Updates editable task fields and refreshes the task list.
  Future<void> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    required int? dueAt,
  }) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.updateTask(
      taskId: taskId,
      title: title,
      note: note,
      priority: priority,
      dueAt: dueAt,
    );
    ref.invalidateSelf();
  }

  /// Transitions `taskId` to `status` and refreshes the task list.
  Future<void> setStatus(String taskId, String status) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.setTaskStatus(taskId: taskId, status: status);
    ref.invalidateSelf();
  }

  /// Moves `taskId` to the trash and refreshes the active task list.
  Future<void> trashTask(String taskId) async {
    final bridge = ref.read(bridgeServiceProvider);
    await bridge.trashTask(taskId: taskId);
    ref.invalidateSelf();
  }
}

final tasksProvider =
    AsyncNotifierProvider.family<TasksNotifier, List<TaskDto>, String>(
      TasksNotifier.new,
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
