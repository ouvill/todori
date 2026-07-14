import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/timer/timer_engine.dart';

import 'support/fake_bridge_service.dart';

void main() {
  for (final surface in ['list-calendar-detail', 'home']) {
    test(
      '$surface completion saves matching work before status and Undo stays idle',
      () async {
        final bridge = _OrderingBridge();
        final list = await bridge.createDefaultList(
          name: 'Inbox',
          sortOrder: 'a0',
        );
        final task = await bridge.createTask(
          listId: list.id,
          title: 'Shared completion',
          due: testDateOnlyDueFromMillis(_todayStartMs()),
        );
        final clock = _MutableClock(DateTime.utc(2026, 7, 13, 12));
        final container = _container(bridge, clock);
        addTearDown(container.dispose);
        await container.read(timerEngineProvider.future);
        await container
            .read(timerEngineProvider.notifier)
            .startStopwatch(taskId: task.id);
        clock.advance(const Duration(minutes: 1));

        if (surface == 'home') {
          await container
              .read(homeTasksProvider.notifier)
              .setStatus(task.id, 'done');
        } else {
          await container
              .read(tasksProvider(list.id).notifier)
              .setStatus(task.id, 'done');
        }

        expect(bridge.operations, ['finish', 'status:done']);
        expect((await bridge.getTasks(listId: list.id)).single.status, 'done');
        expect(await bridge.getActiveTimerSession(), isNull);
        final undo = await container.read(latestTaskUndoProvider.future);
        await container.read(latestTaskUndoProvider.notifier).undo(undo!.id);
        expect((await bridge.getTasks(listId: list.id)).single.status, 'todo');
        expect(await bridge.getActiveTimerSession(), isNull);
      },
    );
  }

  test('timer finish failure preserves task status', () async {
    final bridge = _OrderingBridge(failFinish: true);
    final list = await bridge.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final task = await bridge.createTask(listId: list.id, title: 'Keep open');
    final clock = _MutableClock(DateTime.utc(2026, 7, 13, 13));
    final container = _container(bridge, clock);
    addTearDown(container.dispose);
    await container.read(timerEngineProvider.future);
    await container
        .read(timerEngineProvider.notifier)
        .startStopwatch(taskId: task.id);
    clock.advance(const Duration(minutes: 1));

    await expectLater(
      container
          .read(tasksProvider(list.id).notifier)
          .setStatus(task.id, 'done'),
      throwsA(isA<StateError>()),
    );

    expect(bridge.operations, ['finish']);
    expect((await bridge.getTasks(listId: list.id)).single.status, 'todo');
    expect(await bridge.getActiveTimerSession(), isNotNull);
  });

  test('active break is cleared before external completion', () async {
    final bridge = _OrderingBridge();
    final list = await bridge.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final task = await bridge.createTask(listId: list.id, title: 'Break owner');
    final clock = _MutableClock(DateTime.utc(2026, 7, 13, 13, 30));
    final container = _container(bridge, clock);
    addTearDown(container.dispose);
    await container.read(timerEngineProvider.future);
    await container
        .read(timerEngineProvider.notifier)
        .startPomodoro(taskId: task.id);
    clock.advance(const Duration(minutes: 1));
    await container.read(timerEngineProvider.notifier).finish();
    await container.read(timerEngineProvider.notifier).startBreak();
    bridge.operations.clear();

    await container
        .read(tasksProvider(list.id).notifier)
        .setStatus(task.id, 'done');

    expect(bridge.operations, ['discard', 'status:done']);
    expect((await bridge.getTasks(listId: list.id)).single.status, 'done');
    expect(await bridge.getActiveTimerSession(), isNull);
  });

  test('break discard failure preserves external task status', () async {
    final bridge = _OrderingBridge(failDiscard: true);
    final list = await bridge.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final task = await bridge.createTask(listId: list.id, title: 'Keep break');
    final clock = _MutableClock(DateTime.utc(2026, 7, 13, 13, 45));
    final container = _container(bridge, clock);
    addTearDown(container.dispose);
    await container.read(timerEngineProvider.future);
    await container
        .read(timerEngineProvider.notifier)
        .startPomodoro(taskId: task.id);
    clock.advance(const Duration(minutes: 1));
    await container.read(timerEngineProvider.notifier).finish();
    await container.read(timerEngineProvider.notifier).startBreak();
    bridge.operations.clear();

    await expectLater(
      container
          .read(tasksProvider(list.id).notifier)
          .setStatus(task.id, 'done'),
      throwsA(isA<StateError>()),
    );

    expect(bridge.operations, ['discard']);
    expect((await bridge.getTasks(listId: list.id)).single.status, 'todo');
    expect(await bridge.getActiveTimerSession(), isNotNull);
  });

  test('list lifecycle refreshes Home name and membership', () async {
    final bridge = FakeBridgeService();
    await bridge.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final work = await bridge.createList(name: 'Work', sortOrder: 'a1');
    await bridge.createTask(
      listId: work.id,
      title: 'Visible today',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    final container = _container(bridge, const SystemTimerClock());
    addTearDown(container.dispose);
    expect(
      (await container.read(homeTasksProvider.future)).single.listName,
      'Work',
    );

    await container.read(listsProvider.notifier).renameList(work.id, 'Studio');
    expect(
      (await container.read(homeTasksProvider.future)).single.listName,
      'Studio',
    );
    await container.read(listsProvider.notifier).archiveList(work.id);
    expect(await container.read(homeTasksProvider.future), isEmpty);
    await container.read(archivedListsProvider.notifier).unarchiveList(work.id);
    expect(
      (await container.read(homeTasksProvider.future)).single.listName,
      'Studio',
    );
    await container.read(listsProvider.notifier).deleteList(work.id);
    expect(await container.read(homeTasksProvider.future), isEmpty);
  });

  test('task subtree and list deletion refresh durable active timer', () async {
    final bridge = FakeBridgeService();
    await bridge.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final work = await bridge.createList(name: 'Work', sortOrder: 'a1');
    final parent = await bridge.createTask(listId: work.id, title: 'Parent');
    final child = await bridge.createTask(
      listId: work.id,
      title: 'Child',
      parentTaskId: parent.id,
    );
    final clock = _MutableClock(DateTime.utc(2026, 7, 13, 14));
    final container = _container(bridge, clock);
    addTearDown(container.dispose);
    await container.read(timerEngineProvider.future);
    await container
        .read(timerEngineProvider.notifier)
        .startStopwatch(taskId: child.id);
    await container.read(tasksProvider(work.id).notifier).deleteTask(parent.id);
    expect((await container.read(timerEngineProvider.future)).active, isNull);

    final replacement = await bridge.createTask(
      listId: work.id,
      title: 'Replacement',
    );
    await container
        .read(timerEngineProvider.notifier)
        .startStopwatch(taskId: replacement.id);
    await container.read(listsProvider.notifier).deleteList(work.id);
    expect((await container.read(timerEngineProvider.future)).active, isNull);
  });

  test(
    'sync failure is contained, clears running, retries, and is single-flight',
    () async {
      final bridge = _ControlledSyncBridge()..failuresRemaining = 1;
      await bridge.accountLogin(
        email: 'sync@example.com',
        password: 'password',
      );
      final container = _container(bridge, const SystemTimerClock());
      addTearDown(container.dispose);

      await container.read(syncStatusProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncStatusProvider).requireValue.running, isFalse);
      expect(bridge.attempts, 1);

      await container.read(syncStatusProvider.notifier).syncOnResume();
      expect(bridge.attempts, 2);
      expect(container.read(syncStatusProvider).requireValue.running, isFalse);

      bridge.gate = Completer<void>();
      final first = container.read(syncStatusProvider.notifier).syncNow();
      final second = container.read(syncStatusProvider.notifier).syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.attempts, 3);
      bridge.gate!.complete();
      await Future.wait([first, second]);
      // The two calls share one in-flight run. The second call marks it dirty,
      // so one serial follow-up run completes the realtime contract.
      expect(bridge.attempts, 4);
    },
  );
}

ProviderContainer _container(FakeBridgeService bridge, TimerClock clock) {
  return ProviderContainer(
    overrides: [
      bridgeServiceProvider.overrideWithValue(bridge),
      timerClockProvider.overrideWithValue(clock),
    ],
  );
}

int _todayStartMs() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
}

class _MutableClock implements TimerClock {
  _MutableClock(this.value);
  DateTime value;

  @override
  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

class _OrderingBridge extends FakeBridgeService {
  _OrderingBridge({this.failFinish = false, this.failDiscard = false});

  final bool failFinish;
  final bool failDiscard;
  final operations = <String>[];

  @override
  Future<bool> finishActiveTimerSession({
    required CompletedTimerSessionDto session,
  }) async {
    operations.add('finish');
    if (failFinish) {
      throw StateError('simulated timer save failure');
    }
    return super.finishActiveTimerSession(session: session);
  }

  @override
  Future<bool> discardActiveTimerSession({
    required String expectedSessionId,
  }) async {
    operations.add('discard');
    if (failDiscard) {
      throw StateError('simulated break discard failure');
    }
    return super.discardActiveTimerSession(
      expectedSessionId: expectedSessionId,
    );
  }

  @override
  Future<TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  }) async {
    operations.add('status:$status');
    return super.setTaskStatus(
      taskId: taskId,
      status: status,
      closedReason: closedReason,
    );
  }
}

class _ControlledSyncBridge extends FakeBridgeService {
  int failuresRemaining = 0;
  int attempts = 0;
  Completer<void>? gate;

  @override
  Future<SyncStatusDto> syncNow() async {
    attempts += 1;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('simulated sync failure');
    }
    final currentGate = gate;
    if (currentGate != null) {
      await currentGate.future;
      gate = null;
    }
    return super.syncNow();
  }
}
