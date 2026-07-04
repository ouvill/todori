import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/rust/api.dart';

/// In-memory fake [BridgeService].
///
/// Widget tests use this instead of [FrbBridgeService] so the whole
/// screen/provider/router skeleton can be exercised without the native Rust
/// library and without calling `initCore`.
class FakeBridgeService implements BridgeService {
  final List<ListDto> _lists = [];
  final List<TaskDto> _tasks = [];
  final List<FakeTaskUndoEntry> _undoEntries = [];
  int _listSeq = 0;
  int _taskSeq = 0;
  int _undoSeq = 0;

  @override
  Future<ListDto> createList({
    required String name,
    required String sortOrder,
  }) async {
    final listSeq = _listSeq++;
    final now = _fakeTimestamp(listSeq);
    final list = ListDto(
      id: 'list-$listSeq',
      name: name,
      color: '',
      icon: '',
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    _lists.add(list);
    return list;
  }

  @override
  Future<List<ListDto>> getLists() async => List.unmodifiable(_lists);

  @override
  Future<TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
  }) async {
    final taskSeq = _taskSeq++;
    final siblings =
        _tasks
            .where(
              (task) =>
                  task.listId == listId &&
                  task.parentTaskId == parentTaskId &&
                  task.deletedAt == null,
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
      note: '',
      status: 'todo',
      priority: 0,
      sortOrder: sortOrder,
      createdAt: _fakeTimestamp(100 + taskSeq),
      updatedAt: _fakeTimestamp(100 + taskSeq),
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<List<TaskDto>> getTasks({required String listId}) async {
    final tasks = _tasks
        .where((task) => task.listId == listId && task.deletedAt == null)
        .toList();
    tasks.sort(_compareTasks);
    return tasks;
  }

  @override
  Future<TaskDto> updateTask({
    required String taskId,
    required String title,
    required String note,
    required int priority,
    int? dueAt,
  }) async {
    if (title.trim().isEmpty) {
      throw Exception('task title must not be empty');
    }
    if (priority < 0 || priority > 3) {
      throw Exception('task priority must be between 0 and 3');
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
      dueAt: dueAt,
      scheduledAt: task.scheduledAt,
      estimatedMinutes: task.estimatedMinutes,
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
    final updatedAt = before.updatedAt + _fakeMinuteMs;
    final updated = before._copyWith(
      status: status,
      completedAt: status == 'done' ? updatedAt : null,
      closedReason: closedReason,
      updatedAt: updatedAt,
    );
    _tasks[index] = updated;
    if (status == 'done') {
      _recordUndo(operationType: 'complete', before: before, after: updated);
    }
    return updated;
  }

  @override
  Future<TaskDto> trashTask({required String taskId}) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final before = _tasks[index];
    final updatedAt = before.updatedAt + _fakeMinuteMs;
    final updated = before._copyWith(
      deletedAt: updatedAt,
      updatedAt: updatedAt,
    );
    _tasks[index] = updated;
    if (before.deletedAt == null) {
      _recordUndo(operationType: 'delete', before: before, after: updated);
    }
    return updated;
  }

  @override
  Future<TaskDto> restoreTask({required String taskId}) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final updated = _tasks[index]._copyWithClearDeletedAt();
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<TaskDto> reorderTask({
    required String taskId,
    String? previousTaskId,
    String? nextTaskId,
  }) async {
    if (previousTaskId == taskId || nextTaskId == taskId) {
      throw Exception('task cannot be reordered relative to itself');
    }
    if (previousTaskId != null && previousTaskId == nextTaskId) {
      throw Exception('previous and next task must be different');
    }

    final index = _tasks.indexWhere((task) => task.id == taskId);
    final task = _tasks[index];
    if (task.deletedAt != null) {
      throw Exception('task is deleted');
    }
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
  Future<List<TaskDto>> getTrashedTasks() async {
    return _tasks.where((task) => task.deletedAt != null).toList();
  }

  @override
  Future<TaskUndoDto?> getLatestTaskUndo() async {
    final available = _undoEntries
        .where((entry) => !entry.consumed)
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

  TaskDto _reorderBoundary(String boundaryId, TaskDto task) {
    final boundary = _tasks.singleWhere(
      (candidate) => candidate.id == boundaryId,
    );
    if (boundary.deletedAt != null) {
      throw Exception('task is deleted');
    }
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
}

final int _fakeClockBaseMs = DateTime.utc(2026, 7, 1, 9).millisecondsSinceEpoch;

const int _fakeMinuteMs = Duration.millisecondsPerMinute;

int _fakeTimestamp(int sequence) =>
    _fakeClockBaseMs + (sequence * _fakeMinuteMs);

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

extension _TaskDtoCopy on TaskDto {
  TaskDto _copyWith({
    String? title,
    String? note,
    String? status,
    int? priority,
    int? dueAt,
    int? completedAt,
    String? closedReason,
    int? deletedAt,
    String? sortOrder,
    int? updatedAt,
  }) {
    return TaskDto(
      id: id,
      listId: listId,
      parentTaskId: parentTaskId,
      title: title ?? this.title,
      note: note ?? this.note,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueAt: dueAt ?? this.dueAt,
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
      sortOrder: sortOrder ?? this.sortOrder,
      completedAt: completedAt ?? this.completedAt,
      closedReason: closedReason ?? this.closedReason,
      deletedAt: deletedAt ?? this.deletedAt,
      assignee: assignee,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  TaskDto _copyWithClearDeletedAt() {
    return TaskDto(
      id: id,
      listId: listId,
      parentTaskId: parentTaskId,
      title: title,
      note: note,
      status: status,
      priority: priority,
      dueAt: dueAt,
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
      sortOrder: sortOrder,
      completedAt: completedAt,
      closedReason: closedReason,
      deletedAt: null,
      assignee: assignee,
      createdAt: createdAt,
      updatedAt: updatedAt,
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
