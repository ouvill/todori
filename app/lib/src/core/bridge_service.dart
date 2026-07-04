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

  /// Creates a task using the caller-provided `sortOrder`.
  Future<rust_api.TaskDto> createTask({
    required String listId,
    required String title,
    required String sortOrder,
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

  /// Returns all trashed tasks.
  Future<List<rust_api.TaskDto>> getTrashedTasks();
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
  Future<rust_api.TaskDto> createTask({
    required String listId,
    required String title,
    required String sortOrder,
    String? parentTaskId,
  }) => rust_api.createTask(
    listId: listId,
    title: title,
    sortOrder: sortOrder,
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
  Future<List<rust_api.TaskDto>> getTrashedTasks() =>
      rust_api.getTrashedTasks();
}
