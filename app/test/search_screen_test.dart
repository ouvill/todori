import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/rust/api.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets('search opens from the Home header without moving the heading', (
    tester,
  ) async {
    final fake = await _seedSearchData();
    await _pumpApp(tester, fake);

    final headingTop = tester.getTopLeft(find.text('Home').last).dy;
    final action = find.byTooltip('Search tasks');
    expect(action, findsOneWidget);
    expect(tester.getSize(action), const Size(48, 48));
    expect((tester.getCenter(action).dy - headingTop).abs(), lessThan(36));

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Find what you need.'), findsOneWidget);
  });

  testWidgets('Lists, list tasks and You keep a 48px header search action', (
    tester,
  ) async {
    final fake = await _seedSearchData();
    await _pumpApp(tester, fake);

    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    _expectSearchHitTarget(tester);

    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    _expectSearchHitTarget(tester);

    await tester.tap(find.text('You').last);
    await tester.pumpAndSettle();
    _expectSearchHitTarget(tester);
  });

  testWidgets(
    'empty query is idle; composing input waits; clear restores empty state',
    (tester) async {
      final fake = _RecordingSearchBridge();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      await _pumpApp(tester, fake);
      await _openSearch(tester);

      expect(fake.queries, isEmpty);
      expect(find.text('Find what you need.'), findsOneWidget);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'rev',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      expect(fake.queries, isEmpty);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'rev',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.queries, ['rev']);
      expect(find.text('Nothing found.'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Find what you need.'), findsOneWidget);
    },
  );

  testWidgets(
    'results show title, note, all statuses and archived list context',
    (tester) async {
      final fake = await _seedSearchData();
      await _pumpApp(tester, fake);
      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'review');
      await tester.pumpAndSettle();

      expect(find.text('Review roadmap'), findsOneWidget);
      expect(find.text('Review running'), findsOneWidget);
      expect(find.text('Review shipped'), findsOneWidget);
      expect(find.text('Review skipped'), findsOneWidget);
      expect(find.text('Mentioned only in the review note'), findsOneWidget);
      expect(find.text('To do'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text("Won't do"), findsOneWidget);
      expect(find.text('History · Archived'), findsNWidgets(2));

      final semantics = tester.getSemantics(find.text('Review shipped'));
      expect(
        semantics.label,
        'Review shipped, History · Archived, Done, Priority: None',
      );
    },
  );

  testWidgets('result detail round trip retains query and result set', (
    tester,
  ) async {
    final fake = await _seedSearchData();
    await _pumpApp(tester, fake);
    await _openSearch(tester);
    await tester.enterText(find.byType(TextField), 'roadmap');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review roadmap'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Task actions'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'roadmap'), findsOneWidget);
    expect(find.text('Review roadmap'), findsOneWidget);
  });

  testWidgets('loading, error, retry and zero-result states are explicit', (
    tester,
  ) async {
    final fake = _ControlledSearchBridge();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpApp(tester, fake);
    await _openSearch(tester);

    await tester.enterText(find.byType(TextField), 'slow');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.semantics.byLabel('Searching tasks'), findsOneWidget);

    fake.fail('slow');
    await tester.pumpAndSettle();
    expect(find.text('Search could not be completed.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(fake.queries, ['slow', 'slow']);
    fake.complete('slow', const []);
    await tester.pumpAndSettle();
    expect(find.text('Nothing found.'), findsOneWidget);
    expect(find.text('No tasks match “slow”.'), findsOneWidget);
  });
}

Future<void> _pumpApp(WidgetTester tester, FakeBridgeService fake) async {
  await tester.pumpWidget(
    TodoriApp(
      overrides: [
        bridgeServiceProvider.overrideWithValue(fake),
        taskSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search tasks'));
  await tester.pumpAndSettle();
}

void _expectSearchHitTarget(WidgetTester tester) {
  final action = find.byTooltip('Search tasks');
  expect(action, findsOneWidget);
  expect(tester.getSize(action), const Size(48, 48));
}

Future<FakeBridgeService> _seedSearchData() async {
  final fake = FakeBridgeService();
  final inbox = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final history = await fake.createList(name: 'History', sortOrder: 'a1');
  await fake.createTask(
    listId: inbox.id,
    title: 'Review roadmap',
    note: 'Mentioned only in the review note',
  );
  final inProgress = await fake.createTask(
    listId: inbox.id,
    title: 'Review running',
  );
  final done = await fake.createTask(
    listId: history.id,
    title: 'Review shipped',
  );
  final wontDo = await fake.createTask(
    listId: history.id,
    title: 'Review skipped',
  );
  await fake.setTaskStatus(taskId: inProgress.id, status: 'in_progress');
  await fake.setTaskStatus(taskId: done.id, status: 'done');
  await fake.setTaskStatus(taskId: wontDo.id, status: 'wont_do');
  await fake.archiveList(listId: history.id);
  return fake;
}

class _RecordingSearchBridge extends FakeBridgeService {
  final List<String> queries = [];

  @override
  Future<List<TaskDto>> searchTasks({required String query}) {
    queries.add(query);
    return super.searchTasks(query: query);
  }
}

class _ControlledSearchBridge extends FakeBridgeService {
  final Map<String, List<Completer<List<TaskDto>>>> _requests = {};
  final List<String> queries = [];

  @override
  Future<List<TaskDto>> searchTasks({required String query}) {
    queries.add(query);
    final completer = Completer<List<TaskDto>>();
    _requests.putIfAbsent(query, () => []).add(completer);
    return completer.future;
  }

  void complete(String query, List<TaskDto> tasks) {
    _requests[query]!
        .firstWhere((request) => !request.isCompleted)
        .complete(tasks);
  }

  void fail(String query) {
    _requests[query]!
        .firstWhere((request) => !request.isCompleted)
        .completeError(StateError('search failed'));
  }
}
