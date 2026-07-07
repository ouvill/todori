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
  final List<FakeReorderCall> reorderCalls = [];
  int _listSeq = 0;
  int _taskSeq = 0;
  int _undoSeq = 0;

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
    int? dueAt,
  }) async {
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
      note: '',
      status: 'todo',
      priority: 0,
      dueAt: dueAt,
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

  @override
  Future<List<HomeTaskDto>> getHomeTasks({
    required int todayStartMs,
    required int tomorrowStartMs,
  }) async {
    final activeListById = {
      for (final list in _lists)
        if (list.archivedAt == null) list.id: list,
    };
    final homeTasks = _tasks
        .where((task) {
          final dueAt = task.dueAt;
          if (dueAt == null || !activeListById.containsKey(task.listId)) {
            return false;
          }
          if (task.status == 'todo' || task.status == 'in_progress') {
            return true;
          }
          if (task.status == 'done' || task.status == 'wont_do') {
            final completedAt = task.completedAt;
            return completedAt != null &&
                completedAt >= todayStartMs &&
                completedAt < tomorrowStartMs;
          }
          return false;
        })
        .map(
          (task) => HomeTaskDto(
            task: task,
            listName: activeListById[task.listId]!.name,
          ),
        )
        .toList();
    homeTasks.sort((a, b) => _compareHomeTasks(a.task, b.task));
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
    int? dueAt,
    int? completedAt,
    String? closedReason,
    int? deletedAt,
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
      dueAt: dueAt ?? this.dueAt,
      scheduledAt: scheduledAt,
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

int _compareHomeTasks(TaskDto a, TaskDto b) {
  final dueAt = a.dueAt!.compareTo(b.dueAt!);
  if (dueAt != 0) {
    return dueAt;
  }
  return _compareTasks(a, b);
}

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
