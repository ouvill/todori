import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/bridge_service.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/rust/api.dart';

/// In-memory fake [BridgeService].
///
/// Widget tests use this instead of [FrbBridgeService] so the whole
/// screen/provider/router skeleton can be exercised without the native Rust
/// library and without calling `initCore`.
class FakeBridgeService implements BridgeService {
  final List<ListDto> _lists = [];
  final List<TaskDto> _tasks = [];
  final List<_FakeTaskUndoEntry> _undoEntries = [];
  int _listSeq = 0;
  int _taskSeq = 0;
  int _undoSeq = 0;

  @override
  Future<ListDto> createList({
    required String name,
    required String sortOrder,
  }) async {
    final list = ListDto(
      id: 'list-${_listSeq++}',
      name: name,
      color: '',
      icon: '',
      sortOrder: sortOrder,
      createdAt: 0,
      updatedAt: 0,
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
      id: 'task-${_taskSeq++}',
      listId: listId,
      parentTaskId: parentTaskId,
      title: title,
      note: '',
      status: 'todo',
      priority: 0,
      sortOrder: sortOrder,
      createdAt: 0,
      updatedAt: 0,
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
      updatedAt: task.updatedAt + 1,
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
    final updated = before._copyWith(
      status: status,
      completedAt: status == 'done' ? 1 : null,
      closedReason: closedReason,
      updatedAt: before.updatedAt + 1,
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
    final updated = before._copyWith(
      deletedAt: 1,
      updatedAt: before.updatedAt + 1,
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
    final updated = task._copyWith(
      sortOrder: _fractionalIndexBetween(previous?.sortOrder, next?.sortOrder),
      updatedAt: task.updatedAt + 1,
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
    final id = 'undo-${_undoSeq++}';
    _undoEntries.add(
      _FakeTaskUndoEntry(
        id: id,
        operationType: operationType,
        taskId: before.id,
        before: before,
        afterUpdatedAt: after.updatedAt,
        afterDeletedAt: after.deletedAt,
        afterCompletedAt: after.completedAt,
        createdAt: _undoSeq,
        dto: TaskUndoDto(
          id: id,
          operationType: operationType,
          taskId: before.id,
          listId: before.listId,
          taskTitle: before.title,
          createdAt: _undoSeq,
        ),
      ),
    );
  }
}

class _FakeTaskUndoEntry {
  _FakeTaskUndoEntry({
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

Future<FakeBridgeService> _pumpAppWithSeedData(
  WidgetTester tester, {
  String listName = 'Inbox',
  String taskTitle = 'Buy milk',
}) async {
  final fake = FakeBridgeService();
  await fake.createList(name: listName, sortOrder: 'a0');
  final lists = await fake.getLists();
  await fake.createTask(listId: lists.first.id, title: taskTitle);

  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();

  return fake;
}

void _useNarrowDynamicTypeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

void main() {
  testWidgets('lists screen shows lists from the bridge service', (
    tester,
  ) async {
    await _pumpAppWithSeedData(tester, listName: 'Inbox');

    expect(find.text('Lists'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
  });

  testWidgets('tapping a list navigates to its task list', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Local protection'), findsNothing);
    expect(find.byTooltip('Open trash'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('long task titles survive narrow width and Dynamic Type', (
    tester,
  ) async {
    _useNarrowDynamicTypeView(tester);
    final fake = FakeBridgeService();
    await fake.createList(
      name: 'とても長い日本語のリスト名と English project name',
      sortOrder: 'a0',
    );
    final listId = (await fake.getLists()).first.id;
    final first = await fake.createTask(
      listId: listId,
      title: '四半期レビューのための非常に長いタスクタイトル with detailed English wording',
    );
    final second = await fake.createTask(
      listId: listId,
      title: 'Second task with enough words to wrap on a narrow phone',
    );
    await fake.updateTask(
      taskId: first.id,
      title: first.title,
      note: '',
      priority: 3,
      dueAt: 1,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('とても長い日本語のリスト名と English project name'));
    await tester.pumpAndSettle();

    expect(find.textContaining('四半期レビュー'), findsOneWidget);
    expect(find.textContaining('Second task'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-priority-dot-${first.id}')),
      findsOneWidget,
    );
    expect(find.byTooltip('Move task up'), findsWidgets);
    expect(find.byTooltip('Move task down'), findsWidgets);
    expect(find.text('Local protection'), findsNothing);
    expect(tester.takeException(), isNull);

    final secondMoveUp = find.byKey(ValueKey('task-move-up-${second.id}'));
    await tester.ensureVisible(secondMoveUp);
    await tester.pumpAndSettle();
    await tester.tap(secondMoveUp);
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), [second.id, first.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trash action opens an empty trash screen', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open trash'));
    await tester.pumpAndSettle();

    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Trash is empty.'), findsOneWidget);
    expect(find.text('Deleted tasks will appear here.'), findsOneWidget);
  });

  testWidgets('empty state and create dialog survive narrow Dynamic Type', (
    tester,
  ) async {
    _useNarrowDynamicTypeView(tester);
    final fake = FakeBridgeService();

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No lists yet.'), findsOneWidget);
    expect(find.text('Tap + to create one.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('New list'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a task navigates to its detail screen', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.text('Task detail'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Local protection'), findsOneWidget);
    expect(find.text('Status: To do'), findsOneWidget);
  });

  testWidgets('creating a list via the FAB dialog updates the list', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(tester, listName: 'Inbox');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect((await fake.getLists()).map((list) => list.name), contains('Work'));
  });

  testWidgets('checking a task marks it done through the bridge service', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    final task = (await fake.getTasks(listId: listId)).single;
    final checkboxFinder = find.byKey(ValueKey('task-done-${task.id}'));
    final checkbox = tester.widget<Checkbox>(checkboxFinder);
    expect(checkbox.value, isFalse);

    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(active.single.status, 'done');
    expect(find.text('Task completed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    final updatedCheckbox = tester.widget<Checkbox>(checkboxFinder);
    expect(updatedCheckbox.value, isTrue);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final undone = await fake.getTasks(listId: listId);
    expect(undone.single.status, 'todo');
    final undoneCheckbox = tester.widget<Checkbox>(checkboxFinder);
    expect(undoneCheckbox.value, isFalse);
  });

  testWidgets('task list move buttons reorder root tasks', (tester) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final first = await fake.createTask(listId: listId, title: 'First task');
    final second = await fake.createTask(listId: listId, title: 'Second task');
    final third = await fake.createTask(listId: listId, title: 'Third task');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(find.byKey(ValueKey('task-move-up-${first.id}')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(ValueKey('task-move-down-${third.id}')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(ValueKey('task-move-down-${first.id}')));
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), [second.id, first.id, third.id]);

    final secondTop = tester.getTopLeft(find.text('Second task')).dy;
    final firstTop = tester.getTopLeft(find.text('First task')).dy;
    final thirdTop = tester.getTopLeft(find.text('Third task')).dy;
    expect(secondTop, lessThan(firstTop));
    expect(firstTop, lessThan(thirdTop));
  });

  testWidgets('task list shows three-level subtasks with descendant progress', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(listId: listId, title: 'Plan launch');
    final child = await fake.createTask(
      listId: listId,
      title: 'Draft checklist',
      parentTaskId: parent.id,
    );
    final grandchild = await fake.createTask(
      listId: listId,
      title: 'Review checklist',
      parentTaskId: child.id,
    );
    await fake.setTaskStatus(taskId: grandchild.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Plan launch'), findsOneWidget);
    expect(find.text('Draft checklist'), findsOneWidget);
    expect(find.text('Review checklist'), findsOneWidget);
    expect(find.text('Progress: 1/2'), findsOneWidget);
    expect(find.text('Progress: 1/1'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${child.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${grandchild.id}')),
      findsOneWidget,
    );

    final parentTop = tester.getTopLeft(find.text('Plan launch')).dy;
    final childTop = tester.getTopLeft(find.text('Draft checklist')).dy;
    final grandchildTop = tester.getTopLeft(find.text('Review checklist')).dy;
    expect(parentTop, lessThan(childTop));
    expect(childTop, lessThan(grandchildTop));
  });

  testWidgets('subtask move buttons keep the same parent and depth', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(listId: listId, title: 'Parent');
    final firstChild = await fake.createTask(
      listId: listId,
      title: 'First child',
      parentTaskId: parent.id,
    );
    final secondChild = await fake.createTask(
      listId: listId,
      title: 'Second child',
      parentTaskId: parent.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('task-move-up-${secondChild.id}')));
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(
      active
          .where((task) => task.parentTaskId == parent.id)
          .map((task) => task.id),
      [secondChild.id, firstChild.id],
    );
    expect(
      active.singleWhere((task) => task.id == secondChild.id).parentTaskId,
      parent.id,
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${secondChild.id}')),
      findsOneWidget,
    );

    final parentTop = tester.getTopLeft(find.text('Parent')).dy;
    final secondTop = tester.getTopLeft(find.text('Second child')).dy;
    final firstTop = tester.getTopLeft(find.text('First child')).dy;
    expect(parentTop, lessThan(secondTop));
    expect(secondTop, lessThan(firstTop));
  });

  testWidgets('detail screen creates a subtask under the current task', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Parent task',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parent task'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add subtask'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Child task');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Child task'), findsOneWidget);

    final listId = (await fake.getLists()).first.id;
    final active = await fake.getTasks(listId: listId);
    final parent = active.singleWhere((task) => task.title == 'Parent task');
    final child = active.singleWhere((task) => task.title == 'Child task');
    expect(child.parentTaskId, parent.id);
  });

  testWidgets(
    'incomplete descendants require confirmation before parent done',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Parent task',
      );
      final child = await fake.createTask(
        listId: listId,
        title: 'Child task',
        parentTaskId: parent.id,
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();

      final parentCheckbox = find.byKey(ValueKey('task-done-${parent.id}'));
      await tester.tap(parentCheckbox);
      await tester.pumpAndSettle();

      expect(find.text('Complete parent task?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      var active = await fake.getTasks(listId: listId);
      expect(active.singleWhere((task) => task.id == parent.id).status, 'todo');

      await tester.tap(parentCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      active = await fake.getTasks(listId: listId);
      expect(active.singleWhere((task) => task.id == parent.id).status, 'done');
      expect(active.singleWhere((task) => task.id == child.id).status, 'todo');
    },
  );

  testWidgets('editing a task updates detail, list, and fake bridge state', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Buy oat milk');
    await tester.enterText(find.byType(TextFormField).at(1), 'Shelf-stable');
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Buy oat milk'), findsOneWidget);
    expect(find.text('Shelf-stable'), findsOneWidget);
    expect(find.text('Priority: High'), findsOneWidget);

    final listId = (await fake.getLists()).first.id;
    final active = await fake.getTasks(listId: listId);
    expect(active.single.title, 'Buy oat milk');
    expect(active.single.note, 'Shelf-stable');
    expect(active.single.priority, 3);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Buy oat milk'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-priority-dot-${active.single.id}')),
      findsOneWidget,
    );
  });

  testWidgets('editing a task shows undo and restores previous fields', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Buy oat milk');
    await tester.enterText(find.byType(TextFormField).at(1), 'Shelf-stable');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Task saved.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Undone.'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Shelf-stable'), findsNothing);

    final listId = (await fake.getLists()).first.id;
    final active = await fake.getTasks(listId: listId);
    expect(active.single.title, 'Buy milk');
    expect(active.single.note, '');
  });

  testWidgets('empty title in edit dialog shows validation error', (
    tester,
  ) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required.'), findsOneWidget);
    expect(find.text('Buy milk'), findsWidgets);
  });

  testWidgets('trashed task appears in trash and can be restored', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to trash'));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    expect(await fake.getTasks(listId: listId), isEmpty);
    expect(find.text('Buy milk'), findsNothing);

    await tester.tap(find.byTooltip('Open trash'));
    await tester.pumpAndSettle();

    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Deleted: 1970-01-01'), findsOneWidget);
    expect(find.byTooltip('Restore task'), findsOneWidget);

    final trashed = await fake.getTrashedTasks();
    await tester.tap(find.byKey(ValueKey('restore-task-${trashed.single.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Trash is empty.'), findsOneWidget);
    expect(await fake.getTrashedTasks(), isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(active.single.title, 'Buy milk');
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('trash action shows undo and restores the task', (tester) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to trash'));
    await tester.pumpAndSettle();

    expect(find.text('Task moved to trash.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    final active = await fake.getTasks(listId: listId);
    expect(active.single.title, 'Buy milk');
    expect(await fake.getTrashedTasks(), isEmpty);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('trash rows restore long titles on narrow Dynamic Type', (
    tester,
  ) async {
    _useNarrowDynamicTypeView(tester);
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: '削除済みでも復元できることを確認するための非常に長いタスクタイトル with wrap',
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: '',
      priority: 2,
      dueAt: 1,
    );
    await fake.trashTask(taskId: task.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open trash'));
    await tester.pumpAndSettle();

    expect(find.textContaining('削除済みでも復元'), findsOneWidget);
    expect(find.text('Priority: Medium'), findsOneWidget);
    expect(find.byTooltip('Restore task'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(ValueKey('restore-task-${task.id}')));
    await tester.pumpAndSettle();

    expect(await fake.getTrashedTasks(), isEmpty);
    expect(find.text('Trash is empty.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
