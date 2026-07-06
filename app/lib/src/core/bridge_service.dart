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
  /// Creates a list using the caller-provided `sortOrder`.
  Future<rust_api.ListDto> createList({
    required String name,
    required String sortOrder,
  });

  /// Returns all lists.
  Future<List<rust_api.ListDto>> getLists();

  /// Renames a list.
  Future<rust_api.ListDto> renameList({
    required String listId,
    required String name,
  });

  /// Creates a task at the end of its sibling group.
  Future<rust_api.TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
  });

  /// Returns the active (non-trashed) tasks of `listId`.
  Future<List<rust_api.TaskDto>> getTasks({required String listId});

  /// Updates the editable fields of a task.
  Future<rust_api.TaskDto> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    int? dueAt,
  });

  /// Transitions a task's status.
  Future<rust_api.TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  });

  /// Moves a task to the trash (logical delete).
  Future<rust_api.TaskDto> trashTask({required String taskId});

  /// Restores a previously trashed task.
  Future<rust_api.TaskDto> restoreTask({required String taskId});

  /// Reorders a task within its current sibling group.
  Future<rust_api.TaskDto> reorderTask({
    required String taskId,
    String? previousTaskId,
    String? nextTaskId,
  });

  /// Returns all trashed tasks.
  Future<List<rust_api.TaskDto>> getTrashedTasks();

  /// Returns the latest unconsumed task undo entry, if one exists.
  Future<rust_api.TaskUndoDto?> getLatestTaskUndo();

  /// Applies a task undo entry.
  Future<rust_api.TaskDto> undoTaskOperation({required String undoId});
}

/// Default [BridgeService] implementation backed by the FRB-generated
/// bindings in `src/rust/api.dart`.
class FrbBridgeService implements BridgeService {
  const FrbBridgeService();

  @override
  Future<rust_api.ListDto> createList({
    required String name,
    required String sortOrder,
  }) => rust_api.createList(name: name, sortOrder: sortOrder);

  @override
  Future<List<rust_api.ListDto>> getLists() => rust_api.getLists();

  @override
  Future<rust_api.ListDto> renameList({
    required String listId,
    required String name,
  }) => rust_api.renameList(listId: listId, name: name);

  @override
  Future<rust_api.TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
  }) => rust_api.createTask(
    listId: listId,
    title: title,
    parentTaskId: parentTaskId,
  );

  @override
  Future<List<rust_api.TaskDto>> getTasks({required String listId}) =>
      rust_api.getTasks(listId: listId);

  @override
  Future<rust_api.TaskDto> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    int? dueAt,
  }) => rust_api.updateTask(
    taskId: taskId,
    title: title,
    note: note,
    priority: priority,
    dueAt: dueAt,
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
  Future<rust_api.TaskDto> trashTask({required String taskId}) =>
      rust_api.trashTask(taskId: taskId);

  @override
  Future<rust_api.TaskDto> restoreTask({required String taskId}) =>
      rust_api.restoreTask(taskId: taskId);

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
  Future<List<rust_api.TaskDto>> getTrashedTasks() =>
      rust_api.getTrashedTasks();

  @override
  Future<rust_api.TaskUndoDto?> getLatestTaskUndo() =>
      rust_api.getLatestTaskUndo();

  @override
  Future<rust_api.TaskDto> undoTaskOperation({required String undoId}) =>
      rust_api.undoTaskOperation(undoId: undoId);
}
