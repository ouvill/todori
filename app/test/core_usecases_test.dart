import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/rust/frb_generated.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    await RustLib.init();
    tempDir = await Directory.systemTemp.createTemp('todori_core_usecases_');
    await initCore(dbDir: tempDir.path, defaultInboxName: 'Inbox');
  });

  tearDownAll(() async {
    RustLib.dispose();
    await tempDir.delete(recursive: true);
  });

  test('list and task lifecycle is exposed through Rust bridge', () async {
    final lists = await getLists();
    final defaultList = lists.singleWhere((entry) => entry.isDefault);
    expect(defaultList.name, 'Inbox');

    final list = await createList(name: 'Bridge list', sortOrder: 'a0');
    expect(list.isDefault, isFalse);
    final refreshedLists = await getLists();
    expect(refreshedLists.map((entry) => entry.id), contains(list.id));
    expect(
      refreshedLists.singleWhere((entry) => entry.id == list.id).isDefault,
      isFalse,
    );

    final task = await createTask(
      listId: list.id,
      title: 'Write bridge usecase test',
    );
    expect(task.parentTaskId, isNull);

    final activeTasks = await getTasks(listId: list.id);
    expect(activeTasks.map((entry) => entry.id), contains(task.id));

    final done = await setTaskStatus(taskId: task.id, status: 'done');
    expect(done.status, 'done');
    expect(done.completedAt, isNotNull);

    await deleteTask(taskId: task.id);
    expect(
      (await getTasks(listId: list.id)).map((entry) => entry.id),
      isNot(contains(task.id)),
    );
  });

  test('task reminders are exposed through Rust bridge', () async {
    final list = await createList(name: 'Reminder bridge', sortOrder: 'rb0');
    final task = await createTask(listId: list.id, title: 'Reminder task');
    final remindAt = DateTime.now()
        .add(const Duration(hours: 2))
        .millisecondsSinceEpoch;

    final reminder = await setTaskReminder(taskId: task.id, remindAt: remindAt);

    expect(reminder.taskId, task.id);
    expect(reminder.remindAt, remindAt);
    expect(await getTaskReminders(taskId: task.id), [reminder]);
    expect(
      (await listPendingReminders(
        nowMs: DateTime.now().millisecondsSinceEpoch,
      )).map((entry) => entry.id),
      contains(reminder.id),
    );

    final snoozedUntil = remindAt + const Duration(hours: 1).inMilliseconds;
    final snoozed = await snoozeReminder(
      reminderId: reminder.id,
      snoozedUntil: snoozedUntil,
    );
    expect(snoozed.snoozedUntil, snoozedUntil);

    final cleared = await clearTaskReminders(taskId: task.id);
    expect(cleared.single.id, reminder.id);
    expect(await getTaskReminders(taskId: task.id), isEmpty);
  });

  test('home smart view is exposed through Rust bridge', () async {
    final now = DateTime.now();
    final todayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final tomorrowStart = todayStart + const Duration(days: 1).inMilliseconds;
    final dayAfterTomorrowStart =
        tomorrowStart + const Duration(days: 1).inMilliseconds;
    final todayList = await createList(name: 'Home bridge', sortOrder: 'tb0');
    final otherList = await createList(name: 'Other bridge', sortOrder: 'tb1');
    final archivedList = await createList(
      name: 'Archived bridge',
      sortOrder: 'tb2',
    );
    await archiveList(listId: archivedList.id);

    final dueToday = await createTask(
      listId: todayList.id,
      title: 'Bridge due today',
      dueAt: todayStart,
    );
    final overdue = await createTask(
      listId: otherList.id,
      title: 'Bridge overdue',
      dueAt: todayStart - const Duration(days: 1).inMilliseconds,
    );
    await createTask(listId: todayList.id, title: 'Bridge no due');
    final tomorrow = await createTask(
      listId: todayList.id,
      title: 'Bridge tomorrow',
      dueAt: tomorrowStart,
    );
    final upcoming = await createTask(
      listId: todayList.id,
      title: 'Bridge upcoming',
      dueAt: dayAfterTomorrowStart,
    );
    await createTask(
      listId: archivedList.id,
      title: 'Bridge archived today',
      dueAt: todayStart,
    );
    final closedToday = await createTask(
      listId: otherList.id,
      title: 'Bridge closed today',
      dueAt: todayStart,
    );
    await setTaskStatus(taskId: closedToday.id, status: 'done');

    final homeTasks = await getHomeTasks(
      todayStartMs: todayStart,
      tomorrowStartMs: tomorrowStart,
    );
    final byTitle = {for (final entry in homeTasks) entry.task.title: entry};

    expect(byTitle['Bridge due today']?.task.id, dueToday.id);
    expect(byTitle['Bridge due today']?.listName, 'Home bridge');
    expect(byTitle['Bridge overdue']?.task.id, overdue.id);
    expect(byTitle['Bridge overdue']?.listName, 'Other bridge');
    expect(byTitle['Bridge tomorrow']?.task.id, tomorrow.id);
    expect(byTitle['Bridge upcoming']?.task.id, upcoming.id);
    expect(byTitle['Bridge closed today']?.task.status, 'done');
    expect(byTitle, isNot(contains('Bridge no due')));
    expect(byTitle, isNot(contains('Bridge archived today')));
  });

  test('invalid done to wont_do transition throws', () async {
    final list = await createList(name: 'Transitions', sortOrder: 'b0');
    final task = await createTask(
      listId: list.id,
      title: 'Reject invalid transition',
    );

    await setTaskStatus(taskId: task.id, status: 'done');

    expect(
      () => setTaskStatus(
        taskId: task.id,
        status: 'wont_do',
        closedReason: 'not needed',
      ),
      throwsA(anything),
    );
  });

  test('empty task title throws', () async {
    final list = await createList(name: 'Validation', sortOrder: 'c0');

    expect(() => createTask(listId: list.id, title: '   '), throwsA(anything));
  });

  test('subtask parent id persists through Rust bridge', () async {
    final list = await createList(name: 'Subtasks', sortOrder: 's0');
    final parent = await createTask(listId: list.id, title: 'Parent');
    final child = await createTask(
      listId: list.id,
      title: 'Child',
      parentTaskId: parent.id,
    );
    final grandchild = await createTask(
      listId: list.id,
      title: 'Grandchild',
      parentTaskId: child.id,
    );

    expect(child.parentTaskId, parent.id);
    expect(grandchild.parentTaskId, child.id);

    final active = await getTasks(listId: list.id);
    expect(
      active.singleWhere((task) => task.id == child.id).parentTaskId,
      parent.id,
    );
    expect(
      active.singleWhere((task) => task.id == grandchild.id).parentTaskId,
      child.id,
    );
  });

  test('createTask rejects invalid parent candidates', () async {
    final list = await createList(
      name: 'Subtask parent validation',
      sortOrder: 's1',
    );
    final otherList = await createList(
      name: 'Other subtask parent validation',
      sortOrder: 's2',
    );
    final otherListParent = await createTask(
      listId: otherList.id,
      title: 'Other list parent',
    );

    expect(
      () => createTask(
        listId: list.id,
        title: 'Missing parent child',
        parentTaskId: list.id,
      ),
      throwsA(anything),
    );
    expect(
      () => createTask(
        listId: list.id,
        title: 'Cross-list child',
        parentTaskId: otherListParent.id,
      ),
      throwsA(anything),
    );
  });

  test('createTask assigns fractional sort orders per sibling group', () async {
    final list = await createList(name: 'Generated order', sortOrder: 'g0');
    final first = await createTask(listId: list.id, title: 'First root');
    final second = await createTask(listId: list.id, title: 'Second root');
    final third = await createTask(listId: list.id, title: 'Third root');
    final parent = await createTask(listId: list.id, title: 'Parent');
    final firstChild = await createTask(
      listId: list.id,
      title: 'First child',
      parentTaskId: parent.id,
    );
    final secondChild = await createTask(
      listId: list.id,
      title: 'Second child',
      parentTaskId: parent.id,
    );

    expect(first.sortOrder.compareTo(second.sortOrder), lessThan(0));
    expect(second.sortOrder.compareTo(third.sortOrder), lessThan(0));
    expect(firstChild.sortOrder.compareTo(secondChild.sortOrder), lessThan(0));

    final active = await getTasks(listId: list.id);
    final rootTitles = active
        .where((task) => task.parentTaskId == null)
        .map((task) => task.title)
        .toList();
    expect(rootTitles, ['First root', 'Second root', 'Third root', 'Parent']);
  });

  test('reorderTask persists sibling order through Rust bridge', () async {
    final list = await createList(name: 'Reorder', sortOrder: 'r0');
    final first = await createTask(listId: list.id, title: 'First');
    await createTask(listId: list.id, title: 'Second');
    final third = await createTask(listId: list.id, title: 'Third');

    final moved = await reorderTask(
      taskId: third.id,
      previousTaskId: null,
      nextTaskId: first.id,
    );

    expect(moved.sortOrder.compareTo(first.sortOrder), lessThan(0));
    final active = await getTasks(listId: list.id);
    expect(active.map((task) => task.title), ['Third', 'First', 'Second']);
    expect(
      active.singleWhere((task) => task.id == third.id).parentTaskId,
      isNull,
    );
  });

  test('reorderTask rejects invalid boundaries', () async {
    final list = await createList(name: 'Reorder validation', sortOrder: 'rv0');
    final otherList = await createList(
      name: 'Other reorder validation',
      sortOrder: 'rv1',
    );
    final first = await createTask(listId: list.id, title: 'First');
    final second = await createTask(listId: list.id, title: 'Second');
    final otherListTask = await createTask(
      listId: otherList.id,
      title: 'Other list task',
    );
    final child = await createTask(
      listId: list.id,
      title: 'Child',
      parentTaskId: first.id,
    );

    expect(
      () => reorderTask(taskId: first.id, previousTaskId: first.id),
      throwsA(anything),
    );
    expect(
      () => reorderTask(taskId: first.id, previousTaskId: otherListTask.id),
      throwsA(anything),
    );
    expect(
      () => reorderTask(taskId: second.id, previousTaskId: child.id),
      throwsA(anything),
    );
  });

  test(
    'updateTask persists editable task fields through Rust bridge',
    () async {
      final list = await createList(name: 'Editing', sortOrder: 'd0');
      final task = await createTask(listId: list.id, title: 'Draft title');
      const dueAt = 1782864000000;

      final updated = await updateTask(
        taskId: task.id,
        title: 'Updated title',
        note: 'Updated note',
        priority: 2,
        dueAt: dueAt,
      );

      expect(updated.id, task.id);
      expect(updated.title, 'Updated title');
      expect(updated.note, 'Updated note');
      expect(updated.priority, 2);
      expect(updated.dueAt, dueAt);
      expect(updated.updatedAt, greaterThanOrEqualTo(task.updatedAt));

      final persisted = (await getTasks(
        listId: list.id,
      )).singleWhere((entry) => entry.id == task.id);
      expect(persisted.title, 'Updated title');
      expect(persisted.note, 'Updated note');
      expect(persisted.priority, 2);
      expect(persisted.dueAt, dueAt);

      final cleared = await updateTask(
        taskId: task.id,
        title: 'Updated title',
        note: '',
        priority: 0,
        dueAt: null,
      );
      expect(cleared.note, '');
      expect(cleared.priority, 0);
      expect(cleared.dueAt, isNull);
    },
  );

  test('updateTask rejects priority outside 0 through 3', () async {
    final list = await createList(name: 'Priority validation', sortOrder: 'e0');
    final task = await createTask(
      listId: list.id,
      title: 'Reject invalid priority',
    );

    expect(
      () => updateTask(
        taskId: task.id,
        title: task.title,
        note: task.note,
        priority: 4,
        dueAt: null,
      ),
      throwsA(anything),
    );
  });

  test('complete and edit undo roundtrip through Rust bridge', () async {
    final list = await createList(name: 'Undo lifecycle', sortOrder: 'u0');

    final editTask = await createTask(listId: list.id, title: 'Original title');
    await updateTask(
      taskId: editTask.id,
      title: 'Edited title',
      note: 'Edited note',
      priority: 2,
      dueAt: 1782864000000,
    );
    final editUndo = await getLatestTaskUndo();
    expect(editUndo, isNotNull);
    expect(editUndo!.operationType, 'edit');
    expect(editUndo.taskId, editTask.id);
    final editRestored = await undoTaskOperation(undoId: editUndo.id);
    expect(editRestored.title, 'Original title');
    expect(editRestored.note, '');
    expect(editRestored.priority, 0);
    expect(editRestored.dueAt, isNull);

    final completeTask = await createTask(
      listId: list.id,
      title: 'Complete undo',
    );
    await setTaskStatus(taskId: completeTask.id, status: 'done');
    final completeUndo = await getLatestTaskUndo();
    expect(completeUndo!.operationType, 'complete');
    final completeRestored = await undoTaskOperation(undoId: completeUndo.id);
    expect(completeRestored.status, 'todo');
    expect(completeRestored.completedAt, isNull);

    final wontDoTask = await createTask(listId: list.id, title: 'Wont do undo');
    await setTaskStatus(
      taskId: wontDoTask.id,
      status: 'wont_do',
      closedReason: 'not planned',
    );
    final wontDoUndo = await getLatestTaskUndo();
    expect(wontDoUndo!.operationType, 'complete');
    expect(wontDoUndo.taskId, wontDoTask.id);
    final wontDoRestored = await undoTaskOperation(undoId: wontDoUndo.id);
    expect(wontDoRestored.status, 'todo');
    expect(wontDoRestored.closedReason, isNull);
  });

  test('deleteTask permanently deletes descendants without undo', () async {
    final list = await createList(
      name: 'Permanent task delete',
      sortOrder: 'pd0',
    );
    final parent = await createTask(listId: list.id, title: 'Parent');
    final child = await createTask(
      listId: list.id,
      title: 'Child',
      parentTaskId: parent.id,
    );
    await updateTask(
      taskId: parent.id,
      title: 'Edited parent',
      note: '',
      priority: 0,
      dueAt: null,
    );

    expect(await countTaskDescendants(taskId: parent.id), 1);
    await deleteTask(taskId: parent.id);

    final tasks = await getTasks(listId: list.id);
    expect(tasks.map((task) => task.id), isNot(contains(parent.id)));
    expect(tasks.map((task) => task.id), isNot(contains(child.id)));
    final latestUndo = await getLatestTaskUndo();
    expect(latestUndo?.taskId, isNot(parent.id));
  });

  test(
    'default list can be renamed but cannot be archived or deleted',
    () async {
      final inbox = (await getLists()).singleWhere((list) => list.isDefault);
      final work = await createList(name: 'Delete list', sortOrder: '0001');
      final task = await createTask(listId: work.id, title: 'List task');
      await setTaskStatus(taskId: task.id, status: 'done');

      expect(await countTasksInList(listId: work.id), 1);
      final renamed = await renameList(
        listId: inbox.id,
        name: 'Renamed default inbox',
      );
      expect(renamed.isDefault, isTrue);
      expect(renamed.name, 'Renamed default inbox');
      await expectLater(archiveList(listId: inbox.id), throwsA(anything));
      await expectLater(deleteList(listId: inbox.id), throwsA(anything));

      await deleteList(listId: work.id);
      expect(
        (await getLists()).map((list) => list.id),
        isNot(contains(work.id)),
      );
      expect(await getTasks(listId: work.id), isEmpty);
    },
  );

  test('undo rejects conflicts and consumed entries', () async {
    final list = await createList(name: 'Undo conflicts', sortOrder: 'u1');

    final editTask = await createTask(listId: list.id, title: 'Draft');
    await updateTask(
      taskId: editTask.id,
      title: 'First edit',
      note: '',
      priority: 0,
      dueAt: null,
    );
    final staleEditUndo = (await getLatestTaskUndo())!;
    await updateTask(
      taskId: editTask.id,
      title: 'Second edit',
      note: '',
      priority: 0,
      dueAt: null,
    );
    expect(
      () => undoTaskOperation(undoId: staleEditUndo.id),
      throwsA(anything),
    );

    final completeTask = await createTask(
      listId: list.id,
      title: 'Complete then delete',
    );
    await setTaskStatus(taskId: completeTask.id, status: 'done');
    final completeUndo = (await getLatestTaskUndo())!;
    await deleteTask(taskId: completeTask.id);
    expect(() => undoTaskOperation(undoId: completeUndo.id), throwsA(anything));

    final consumedTask = await createTask(listId: list.id, title: 'Consumed');
    await setTaskStatus(taskId: consumedTask.id, status: 'done');
    final consumedUndo = (await getLatestTaskUndo())!;
    await undoTaskOperation(undoId: consumedUndo.id);
    expect(() => undoTaskOperation(undoId: consumedUndo.id), throwsA(anything));
  });

  test('settings roundtrip through Rust bridge', () async {
    const key = 'ui_mode';

    await setSetting(key: key, value: 'simple');
    expect(await getSetting(key: key), 'simple');

    await setSetting(key: key, value: 'advanced');
    expect(await getSetting(key: key), 'advanced');
    expect(await getSetting(key: 'missing_bridge_setting'), isNull);
  });
}
