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
  int _listSeq = 0;
  int _taskSeq = 0;

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
    required String sortOrder,
    String? parentTaskId,
  }) async {
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
    return _tasks
        .where((task) => task.listId == listId && task.deletedAt == null)
        .toList();
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
    return updated;
  }

  @override
  Future<TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  }) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final updated = _tasks[index]._copyWith(
      status: status,
      completedAt: status == 'done' ? 1 : null,
      closedReason: closedReason,
    );
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<TaskDto> trashTask({required String taskId}) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final updated = _tasks[index]._copyWith(deletedAt: 1);
    _tasks[index] = updated;
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
  Future<List<TaskDto>> getTrashedTasks() async {
    return _tasks.where((task) => task.deletedAt != null).toList();
  }
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
      sortOrder: sortOrder,
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

Future<FakeBridgeService> _pumpAppWithSeedData(
  WidgetTester tester, {
  String listName = 'Inbox',
  String taskTitle = 'Buy milk',
}) async {
  final fake = FakeBridgeService();
  await fake.createList(name: listName, sortOrder: 'a0');
  final lists = await fake.getLists();
  await fake.createTask(
    listId: lists.first.id,
    title: taskTitle,
    sortOrder: 'a0',
  );

  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();

  return fake;
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
    expect(find.text('Local protection'), findsOneWidget);
    expect(find.byTooltip('Open trash'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
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

    final updatedCheckbox = tester.widget<Checkbox>(checkboxFinder);
    expect(updatedCheckbox.value, isTrue);
  });

  testWidgets('task list shows three-level subtasks with descendant progress', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Plan launch',
      sortOrder: 'a0',
    );
    final child = await fake.createTask(
      listId: listId,
      title: 'Draft checklist',
      sortOrder: 'a0',
      parentTaskId: parent.id,
    );
    final grandchild = await fake.createTask(
      listId: listId,
      title: 'Review checklist',
      sortOrder: 'a0',
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
        sortOrder: 'a0',
      );
      final child = await fake.createTask(
        listId: listId,
        title: 'Child task',
        sortOrder: 'a0',
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
}
