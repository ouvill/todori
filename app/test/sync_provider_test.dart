import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/src/core/providers.dart';

import 'support/fake_bridge_service.dart';
import 'support/fake_realtime.dart';

void main() {
  test('sync provider stays idle when signed out', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final status = await container.read(syncStatusProvider.future);

    expect(status.loggedIn, isFalse);
    expect(fake.syncNowCalls, 0);
  });

  test('sync provider triggers after login and foreground resume', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    await container.read(syncStatusProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(fake.syncNowCalls, greaterThanOrEqualTo(1));
    final callsAfterLogin = fake.syncNowCalls;

    await container.read(syncStatusProvider.notifier).syncOnResume();

    expect(fake.syncNowCalls, greaterThan(callsAfterLogin));
  });

  test('sync now refreshes list-scoped tasks', () async {
    final fake = FakeBridgeService();
    final container = ProviderContainer(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container
        .read(accountProvider.notifier)
        .login(email: 'alice@example.com', password: 'correct password');
    final list = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    expect(await container.read(tasksProvider(list.id).future), isEmpty);

    fake.addRemoteTaskForNextSync(
      listId: list.id,
      title: 'Pulled task without due date',
    );
    await container.read(syncStatusProvider.notifier).syncNow();

    final tasks = await container.read(tasksProvider(list.id).future);
    expect(
      tasks.map((task) => task.title),
      contains('Pulled task without due date'),
    );
  });

  test(
    'every list and task sync mutation reaches the common debounce',
    () async {
      final fake = FakeBridgeService();
      final timers = FakeRealtimeTimers();
      final container = ProviderContainer(
        overrides: [
          bridgeServiceProvider.overrideWithValue(fake),
          realtimeTimerFactoryProvider.overrideWithValue(timers.create),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(accountProvider.notifier)
          .login(email: 'alice@example.com', password: 'correct password');
      await container.read(syncStatusProvider.future);
      await _pumpAsync();

      Future<void> expectDebouncedSync(Future<void> Function() mutation) async {
        final before = fake.syncNowCalls;
        await mutation();
        timers.activeWithDelay(const Duration(milliseconds: 250)).fire();
        await _pumpAsync();
        expect(fake.syncNowCalls, before + 1);
      }

      await expectDebouncedSync(
        () => container.read(listsProvider.notifier).createList('Realtime'),
      );
      var list = (await container.read(listsProvider.future)).single;
      await expectDebouncedSync(
        () => container
            .read(listsProvider.notifier)
            .renameList(list.id, 'Renamed'),
      );
      list = (await container.read(listsProvider.future)).single;
      await expectDebouncedSync(
        () => container.read(listsProvider.notifier).archiveList(list.id),
      );
      await expectDebouncedSync(
        () => container
            .read(archivedListsProvider.notifier)
            .unarchiveList(list.id),
      );

      final tasks = container.read(tasksProvider(list.id).notifier);
      await expectDebouncedSync(() => tasks.createTask('First'));
      await expectDebouncedSync(() => tasks.createTask('Second'));
      var taskRows = await container.read(tasksProvider(list.id).future);
      final first = taskRows.first;
      final second = taskRows.last;
      await expectDebouncedSync(
        () => tasks.updateTask(
          taskId: first.id,
          title: 'Edited',
          note: first.note,
          priority: first.priority,
          due: first.due,
          scheduledAt: first.scheduledAt,
          estimatedMinutes: first.estimatedMinutes,
        ),
      );
      final undo = await container.read(latestTaskUndoProvider.future);
      await expectDebouncedSync(
        () => container.read(latestTaskUndoProvider.notifier).undo(undo!.id),
      );
      await expectDebouncedSync(() => tasks.setStatus(first.id, 'in_progress'));
      await expectDebouncedSync(
        () => tasks.reorderTask(
          taskId: second.id,
          previousTaskId: null,
          nextTaskId: first.id,
        ),
      );
      await expectDebouncedSync(() => tasks.deleteTask(second.id));

      taskRows = await container.read(tasksProvider(list.id).future);
      expect(taskRows, hasLength(1));
      await expectDebouncedSync(
        () => container.read(listsProvider.notifier).deleteList(list.id),
      );
    },
  );
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
