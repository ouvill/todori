import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/rust/api.dart';

import 'support/fake_bridge_service.dart';

void main() {
  test(
    'fake search uses title and note prefix AND across task states',
    () async {
      final fake = FakeBridgeService();
      final active = await fake.createList(name: 'Active', sortOrder: 'a0');
      final archived = await fake.createList(name: 'Archive', sortOrder: 'a1');
      final todo = await fake.createTask(
        listId: active.id,
        title: 'Plan Kyoto trip',
        note: 'Book shinkansen',
      );
      final inProgress = await fake.createTask(
        listId: active.id,
        title: 'Planning notes',
        note: 'Kyoto hotels',
      );
      final done = await fake.createTask(
        listId: archived.id,
        title: 'Plan archive',
        note: 'Kyoto result',
      );
      final wontDo = await fake.createTask(
        listId: archived.id,
        title: 'Plan skipped',
        note: 'Kyoto alternative',
      );
      await fake.setTaskStatus(taskId: inProgress.id, status: 'in_progress');
      await fake.setTaskStatus(taskId: done.id, status: 'done');
      await fake.setTaskStatus(taskId: wontDo.id, status: 'wont_do');
      await fake.archiveList(listId: archived.id);

      final results = await fake.searchTasks(query: 'pla kyo');
      expect(results.map((task) => task.id), [
        todo.id,
        inProgress.id,
        done.id,
        wontDo.id,
      ]);

      await fake.deleteTask(taskId: todo.id);
      expect(
        (await fake.searchTasks(query: 'plan kyoto')).map((task) => task.id),
        isNot(contains(todo.id)),
      );
    },
  );

  test('provider keeps empty query idle without calling bridge', () {
    final fake = _ControlledSearchBridge();
    final container = _container(fake);
    addTearDown(container.dispose);

    container.read(taskSearchProvider.notifier).setQuery('   ');

    expect(container.read(taskSearchProvider), isA<TaskSearchIdle>());
    expect(fake.queries, isEmpty);
  });

  test('provider cancels the superseded debounce timer', () async {
    final fake = _ControlledSearchBridge();
    final container = ProviderContainer(
      overrides: [
        bridgeServiceProvider.overrideWithValue(fake),
        taskSearchDebounceDurationProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    container.listen(taskSearchProvider, (_, _) {});
    addTearDown(container.dispose);
    final notifier = container.read(taskSearchProvider.notifier);

    notifier.setQuery('old');
    notifier.setQuery('new');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(fake.queries, ['new']);
    fake.complete('new', const []);
    await _flush();
    expect(
      container.read(taskSearchProvider),
      isA<TaskSearchData>().having((state) => state.query, 'query', 'new'),
    );
  });

  test('provider composes active and archived list context', () async {
    final fake = FakeBridgeService();
    final active = await fake.createList(name: 'Work', sortOrder: 'a0');
    final archived = await fake.createList(name: 'History', sortOrder: 'a1');
    await fake.createTask(listId: active.id, title: 'Review active');
    await fake.createTask(listId: archived.id, title: 'Review archived');
    await fake.archiveList(listId: archived.id);
    final container = _container(fake);
    addTearDown(container.dispose);

    container.read(taskSearchProvider.notifier).setQuery('rev');
    expect(container.read(taskSearchProvider), isA<TaskSearchLoading>());
    await _flush();

    final state = container.read(taskSearchProvider) as TaskSearchData;
    expect(state.query, 'rev');
    expect(state.items.map((item) => item.listName), ['Work', 'History']);
    expect(state.items.map((item) => item.listArchived), [false, true]);
  });

  test('stale success and error cannot replace a newer query', () async {
    final fake = _ControlledSearchBridge();
    final list = await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final oldTask = await fake.createTask(listId: list.id, title: 'Old');
    final newTask = await fake.createTask(listId: list.id, title: 'New');
    final container = _container(fake);
    addTearDown(container.dispose);
    final notifier = container.read(taskSearchProvider.notifier);

    notifier.setQuery('old');
    notifier.setQuery('new');
    fake.complete('new', [newTask]);
    await _flush();
    var state = container.read(taskSearchProvider) as TaskSearchData;
    expect(state.query, 'new');
    expect(state.items.single.task.id, newTask.id);

    fake.complete('old', [oldTask]);
    await _flush();
    state = container.read(taskSearchProvider) as TaskSearchData;
    expect(state.query, 'new');

    notifier.setQuery('failure');
    notifier.setQuery('latest');
    fake.fail('failure');
    fake.complete('latest', [newTask]);
    await _flush();
    state = container.read(taskSearchProvider) as TaskSearchData;
    expect(state.query, 'latest');
  });

  test('latest bridge failure becomes explicit error state', () async {
    final fake = _ControlledSearchBridge();
    final container = _container(fake);
    addTearDown(container.dispose);

    container.read(taskSearchProvider.notifier).setQuery('broken');
    fake.fail('broken');
    await _flush();

    final state = container.read(taskSearchProvider) as TaskSearchError;
    expect(state.query, 'broken');
    expect(state.error, isA<StateError>());
  });
}

ProviderContainer _container(FakeBridgeService fake) {
  final container = ProviderContainer(
    overrides: [
      bridgeServiceProvider.overrideWithValue(fake),
      taskSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
    ],
  );
  container.listen(taskSearchProvider, (_, _) {});
  return container;
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ControlledSearchBridge extends FakeBridgeService {
  final Map<String, Completer<List<TaskDto>>> _requests = {};
  final List<String> queries = [];

  @override
  Future<List<TaskDto>> searchTasks({required String query}) {
    queries.add(query);
    return _requests.putIfAbsent(query, Completer<List<TaskDto>>.new).future;
  }

  void complete(String query, List<TaskDto> tasks) {
    _requests.putIfAbsent(query, Completer<List<TaskDto>>.new).complete(tasks);
  }

  void fail(String query) {
    _requests
        .putIfAbsent(query, Completer<List<TaskDto>>.new)
        .completeError(StateError('search failed'));
  }
}
