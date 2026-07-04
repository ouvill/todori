import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/rust/frb_generated.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    await RustLib.init();
    tempDir = await Directory.systemTemp.createTemp('todori_core_usecases_');
    await initCore(dbDir: tempDir.path);
  });

  tearDownAll(() async {
    RustLib.dispose();
    await tempDir.delete(recursive: true);
  });

  test('list and task lifecycle is exposed through Rust bridge', () async {
    final list = await createList(name: 'Inbox', sortOrder: 'a0');

    final lists = await getLists();
    expect(lists.map((entry) => entry.id), contains(list.id));

    final task = await createTask(
      listId: list.id,
      title: 'Write bridge usecase test',
      sortOrder: 'a0',
    );

    final activeTasks = await getTasks(listId: list.id);
    expect(activeTasks.map((entry) => entry.id), contains(task.id));

    final done = await setTaskStatus(taskId: task.id, status: 'done');
    expect(done.status, 'done');
    expect(done.completedAt, isNotNull);

    final trashed = await trashTask(taskId: task.id);
    expect(trashed.deletedAt, isNotNull);
    expect(
      (await getTasks(listId: list.id)).map((entry) => entry.id),
      isNot(contains(task.id)),
    );
    expect(
      (await getTrashedTasks()).map((entry) => entry.id),
      contains(task.id),
    );

    final restored = await restoreTask(taskId: task.id);
    expect(restored.deletedAt, isNull);
    expect(
      (await getTasks(listId: list.id)).map((entry) => entry.id),
      contains(task.id),
    );
  });

  test('invalid done to wont_do transition throws', () async {
    final list = await createList(name: 'Transitions', sortOrder: 'b0');
    final task = await createTask(
      listId: list.id,
      title: 'Reject invalid transition',
      sortOrder: 'a0',
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

    expect(
      () => createTask(listId: list.id, title: '   ', sortOrder: 'a0'),
      throwsA(anything),
    );
  });

  test(
    'updateTask persists editable task fields through Rust bridge',
    () async {
      final list = await createList(name: 'Editing', sortOrder: 'd0');
      final task = await createTask(
        listId: list.id,
        title: 'Draft title',
        sortOrder: 'a0',
      );
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
      sortOrder: 'a0',
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
}
