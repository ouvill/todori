import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/ui/task_components.dart';

import 'support/fake_bridge_service.dart';

Future<FakeBridgeService> _pumpAppWithSeedData(
  WidgetTester tester, {
  String listName = 'Inbox',
  String taskTitle = 'Buy milk',
}) async {
  final fake = FakeBridgeService();
  await fake.createDefaultList(name: listName, sortOrder: 'a0');
  final lists = await fake.getLists();
  final defaultList = lists.singleWhere((list) => list.isDefault);
  await fake.createTask(
    listId: defaultList.id,
    title: taskTitle,
    dueAt: _todayStartMs(),
  );

  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();

  return fake;
}

int _todayStartMs() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
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

Future<void> _selectTaskSortMode(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Sort tasks'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openListsScreen(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open lists'));
  await tester.pumpAndSettle();
}

Future<void> _openListFromHome(WidgetTester tester, String listName) async {
  await _openListsScreen(tester);
  await tester.tap(find.text(listName).last);
  await tester.pumpAndSettle();
}

void _expectTaskTitleOrder(WidgetTester tester, List<String> titles) {
  final tops = [
    for (final title in titles) tester.getTopLeft(find.text(title)).dy,
  ];
  for (var index = 1; index < tops.length; index += 1) {
    expect(tops[index - 1], lessThan(tops[index]));
  }
}

Future<void> _dragTaskOnto(
  WidgetTester tester, {
  required String sourceTaskId,
  required String targetTaskId,
  required bool dropAfterTarget,
}) async {
  final source = find.byKey(ValueKey('task-row-$sourceTaskId'));
  final target = find.byKey(ValueKey('task-drop-target-$targetTaskId'));
  await tester.ensureVisible(source);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();

  final targetRect = tester.getRect(target);
  final targetPoint = dropAfterTarget
      ? targetRect.bottomCenter.translate(0, -4)
      : targetRect.topCenter.translate(0, 4);
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(targetPoint);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void _expectNoVisibleMoveButtons() {
  expect(find.byTooltip('Move task up'), findsNothing);
  expect(find.byTooltip('Move task down'), findsNothing);
}

List<String> _customActionLabels(SemanticsNode node) {
  return [
    for (final id
        in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
      ?CustomSemanticsAction.getAction(id)?.label,
  ];
}

SemanticsFinder _reorderSemanticsFinder(String actionLabel) {
  return find.semantics.byPredicate(
    (node) => _customActionLabels(node).contains(actionLabel),
  );
}

void main() {
  testWidgets('lists screen shows lists from the bridge service', (
    tester,
  ) async {
    await _pumpAppWithSeedData(tester, listName: 'Inbox');
    await _openListsScreen(tester);

    expect(find.text('LISTS'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
  });

  testWidgets('lists screen enters from the leading edge', (tester) async {
    await _pumpAppWithSeedData(tester, listName: 'Inbox');

    await tester.tap(find.byTooltip('Open lists'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final slideOffsets = tester
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .map((transition) => transition.position.value.dx);
    expect(slideOffsets.any((dx) => dx < 0), isTrue);
  });

  testWidgets('tapping a list navigates to its task list', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.byTooltip('Open lists'), findsOneWidget);
    expect(find.text('Add task'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await _openListFromHome(tester, 'Inbox');

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Local protection'), findsNothing);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets(
    'home shows four due sections across active lists with list labels',
    (tester) async {
      final fake = FakeBridgeService();
      final today = _todayStartMs();
      final tomorrow = today + const Duration(days: 1).inMilliseconds;
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final work = await fake.createList(name: 'Work', sortOrder: 'a1');
      final archived = await fake.createList(
        name: 'Old project',
        sortOrder: 'a2',
      );
      await fake.archiveList(listId: archived.id);
      final inbox = (await fake.getLists()).singleWhere(
        (list) => list.isDefault,
      );

      final inboxDueToday = await fake.createTask(
        listId: inbox.id,
        title: 'Inbox due today',
        dueAt: today,
      );
      await fake.createTask(
        listId: work.id,
        title: 'Work overdue',
        dueAt: today - const Duration(days: 1).inMilliseconds,
      );
      await fake.createTask(listId: work.id, title: 'No due work');
      await fake.createTask(
        listId: work.id,
        title: 'Tomorrow work',
        dueAt: tomorrow,
      );
      await fake.createTask(
        listId: work.id,
        title: 'Upcoming work',
        dueAt: tomorrow + const Duration(days: 1).inMilliseconds,
      );
      await fake.createTask(
        listId: archived.id,
        title: 'Archived today',
        dueAt: today,
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Tomorrow'), findsWidgets);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Inbox due today'), findsOneWidget);
      expect(find.text('Work overdue'), findsOneWidget);
      expect(find.text('Tomorrow work'), findsOneWidget);
      expect(find.text('Upcoming work'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Work'), findsWidgets);
      expect(find.text('No due work'), findsNothing);
      expect(find.text('Archived today'), findsNothing);
      expect(find.byTooltip('List actions'), findsNothing);
      expect(find.byTooltip('Move task up'), findsNothing);
      expect(find.byTooltip('Move task down'), findsNothing);
      expect(
        find.byKey(ValueKey('task-drop-target-${inboxDueToday.id}')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Sort tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Manual'), findsNothing);
      expect(find.text('Due date'), findsOneWidget);
      await tester.tap(find.text('Due date').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tomorrow').first);
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow work'), findsNothing);
      await tester.tap(find.text('Tomorrow').first);
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow work'), findsOneWidget);
    },
  );

  testWidgets('home add task creates in default inbox with today due date', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Today capture');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final defaultList = (await fake.getLists()).singleWhere(
      (list) => list.isDefault,
    );
    final tasks = await fake.getTasks(listId: defaultList.id);
    expect(tasks.single.title, 'Today capture');
    expect(tasks.single.dueAt, _todayStartMs());
    expect(find.text('Today capture'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
  });

  testWidgets('lists screen puts Home first and Home row returns home', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');
    final archived = await fake.createList(
      name: 'Old project',
      sortOrder: 'a2',
    );
    await fake.archiveList(listId: archived.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);

    expect(
      tester.getTopLeft(find.text('Home')).dy,
      lessThan(tester.getTopLeft(find.text('Inbox')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Work')).dy,
      lessThan(tester.getTopLeft(find.text('New list')).dy),
    );
    expect(
      tester.getTopLeft(find.text('New list')).dy,
      lessThan(tester.getTopLeft(find.text('Archived (1)')).dy),
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open lists'), findsOneWidget);
    expect(find.text('Add task'), findsOneWidget);
  });

  testWidgets(
    'home shows due subtask without parent context and normal list omits list label',
    (tester) async {
      final fake = FakeBridgeService();
      final today = _todayStartMs();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final inbox = (await fake.getLists()).singleWhere(
        (list) => list.isDefault,
      );
      final parent = await fake.createTask(
        listId: inbox.id,
        title: 'Parent without due',
      );
      final child = await fake.createTask(
        listId: inbox.id,
        title: 'Due child only',
        parentTaskId: parent.id,
        dueAt: today,
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Due child only'), findsOneWidget);
      expect(find.text('Parent without due'), findsNothing);
      expect(find.text('Inbox'), findsOneWidget);
      expect(
        find.byKey(ValueKey('task-hierarchy-guide-${child.id}')),
        findsNothing,
      );

      await _openListFromHome(tester, 'Inbox');
      expect(find.text('Due child only'), findsOneWidget);
      expect(find.text('Parent without due'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);
      expect(
        find.byKey(ValueKey('task-drop-target-${child.id}')),
        findsOneWidget,
      );
      _expectNoVisibleMoveButtons();
    },
  );

  testWidgets('long task titles survive narrow width and Dynamic Type', (
    tester,
  ) async {
    _useNarrowDynamicTypeView(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(
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
    await _openListFromHome(tester, 'とても長い日本語のリスト名と English project name');

    expect(find.textContaining('四半期レビュー'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-priority-dot-${first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-drop-target-${second.id}')),
      findsOneWidget,
    );
    _expectNoVisibleMoveButtons();
    expect(find.text('Local protection'), findsNothing);
    expect(tester.takeException(), isNull);

    // Scroll by hunting for the target rather than a fixed pixel delta: the
    // compact row layout (task-30) lets a very long wrapped title occupy
    // more vertical space than a fixed drag distance can predict.
    await tester.scrollUntilVisible(find.textContaining('Second task'), 220);
    await tester.pumpAndSettle();
    expect(find.textContaining('Second task'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    tester.semantics.customAction(
      _reorderSemanticsFinder('Move task up'),
      const CustomSemanticsAction(label: 'Move task up'),
    );
    await tester.pumpAndSettle();
    semantics.dispose();

    final active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), [second.id, first.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default inbox empty tasks and create dialog survive narrow Dynamic Type',
    (tester) async {
      _useNarrowDynamicTypeView(tester);
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Add task'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();

      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('polished list, sort, detail, and dialog surfaces stay stable', (
    tester,
  ) async {
    _useNarrowDynamicTypeView(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(
      name: '受信箱とても長いリスト名 with a product screenshot length',
      sortOrder: 'a0',
    );
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'README screenshot前に確認する非常に長いタスクタイトル with English detail',
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: '長いnoteでも詳細画面で読みやすく折り返すことを確認するための説明文です。',
      priority: 3,
      dueAt: 1,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('受信箱'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _openListFromHome(
      tester,
      '受信箱とても長いリスト名 with a product screenshot length',
    );
    await tester.tap(find.byTooltip('Sort tasks'));
    await tester.pumpAndSettle();

    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Due date'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Manual').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('README screenshot'));
    await tester.pumpAndSettle();

    expect(find.text('Task detail'), findsOneWidget);
    expect(find.textContaining('長いnoteでも詳細画面'), findsOneWidget);
    // Priority is conveyed in the metadata row, not beside the title or via
    // the removed edit dialog.
    expect(find.byTooltip('Priority: High'), findsOneWidget);
    final titleFinder = find.textContaining('README screenshot');
    final titleBottomY = tester.getBottomLeft(titleFinder).dy;
    final dotCenterY = tester
        .getCenter(find.byKey(ValueKey('task-priority-dot-${task.id}')))
        .dy;
    expect(dotCenterY, greaterThan(titleBottomY));

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(titleFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task-title-inline-field')),
      findsOneWidget,
    );
    expect(find.text('Edit task'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a task navigates to its detail screen', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.text('Task detail'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    // No persistent Local protection/lock chip in the main task UI (see
    // `docs/design/visual-direction.md` Security Signal section); status
    // keeps a short, unprefixed pill in the detail header.
    expect(find.text('Local protection'), findsNothing);
    expect(find.text('To do'), findsOneWidget);
  });

  testWidgets('creating a list from list management updates the list', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(tester, listName: 'Inbox');

    await _openListsScreen(tester);
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect((await fake.getLists()).map((list) => list.name), contains('Work'));
  });

  testWidgets('list rows expose navigation without row actions or chevrons', (
    tester,
  ) async {
    await _pumpAppWithSeedData(tester, listName: 'Inbox');

    await _openListsScreen(tester);

    expect(find.byTooltip('List actions'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('New list'), findsOneWidget);

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Tasks'), findsOneWidget);
  });

  testWidgets(
    'renaming the first list from the task screen updates the fake bridge service',
    (tester) async {
      final fake = await _pumpAppWithSeedData(tester, listName: 'Inbox');

      await _openListFromHome(tester, 'Inbox');
      await tester.tap(find.byTooltip('List actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Personal');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final lists = await fake.getLists();
      expect(lists.singleWhere((list) => list.isDefault).name, 'Personal');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Personal'), findsOneWidget);
    },
  );

  testWidgets('rename dialog handles a long list name', (tester) async {
    _useNarrowDynamicTypeView(tester);
    const longListName = 'とても長い既定インボックス名 with a long English project label';
    await _pumpAppWithSeedData(tester, listName: longListName);

    await _openListFromHome(tester, longListName);
    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, longListName);
    expect(find.text('Rename list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archiving a list moves it to the archived section', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect((await fake.getLists()).map((list) => list.name), ['Inbox']);
    expect((await fake.getArchivedLists()).map((list) => list.name), ['Work']);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Unarchive'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsNothing);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.text('Unarchive'), findsNothing);
  });

  testWidgets('unarchiving a list returns it to the active list section', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final work = await fake.createList(name: 'Work', sortOrder: 'a1');
    await fake.archiveList(listId: work.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);
    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unarchive'));
    await tester.pumpAndSettle();

    expect((await fake.getArchivedLists()), isEmpty);
    expect((await fake.getLists()).map((list) => list.name), ['Inbox', 'Work']);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Archived (1)'), findsNothing);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('default inbox does not expose archive action', (tester) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets(
    'list delete confirms impact count and removes non-default list',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final work = await fake.createList(name: 'Work', sortOrder: 'a1');
      await fake.createTask(listId: work.id, title: 'Open work');
      final completed = await fake.createTask(
        listId: work.id,
        title: 'Done work',
      );
      await fake.setTaskStatus(taskId: completed.id, status: 'done');

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await _openListsScreen(tester);
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('List actions'));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Archive')).dy,
        lessThan(tester.getTopLeft(find.text('Delete')).dy),
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Work?'), findsOneWidget);
      expect(find.textContaining('2 tasks'), findsOneWidget);
      expect(find.textContaining('including completed tasks'), findsOneWidget);
      expect(find.textContaining('Archive the list instead'), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect((await fake.getLists()).map((list) => list.name), ['Inbox']);
      expect(await fake.getTasks(listId: work.id), isEmpty);
      expect(find.text('Work'), findsNothing);
    },
  );

  testWidgets('archived section is hidden when there are no archived lists', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);

    expect(find.textContaining('Archived'), findsNothing);
    expect(find.byTooltip('Show archived lists'), findsNothing);
  });

  testWidgets('archived lists still navigate to their task screen', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final archive = await fake.createList(name: 'Archive me', sortOrder: 'a1');
    await fake.createTask(listId: archive.id, title: 'Kept history task');
    await fake.archiveList(listId: archive.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);
    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive me'));
    await tester.pumpAndSettle();

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Kept history task'), findsOneWidget);
    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    expect(find.text('Unarchive'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Edit task'), findsNothing);
  });

  testWidgets('checking a task marks it done through the bridge service', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    final listId = (await fake.getLists()).first.id;
    final task = (await fake.getTasks(listId: listId)).single;
    final checkboxFinder = find.byKey(ValueKey('task-done-${task.id}'));
    final checkbox = tester.widget<Checkbox>(checkboxFinder);
    expect(checkbox.value, isFalse);

    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(active.single.status, 'done');
    expect(find.text('Task closed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    final doneCheckbox = tester.widget<Checkbox>(checkboxFinder);
    expect(doneCheckbox.value, isTrue);
    expect(doneCheckbox.onChanged, isNotNull);
    expect(find.byTooltip('Reopen task'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final undone = await fake.getTasks(listId: listId);
    expect(undone.single.status, 'todo');
    final undoneCheckbox = tester.widget<Checkbox>(checkboxFinder);
    expect(undoneCheckbox.value, isFalse);
    expect(find.text('Closed'), findsNothing);
  });

  testWidgets('done root row leading control reopens without undo', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Done task',
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: task.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Done task'), findsOneWidget);
    expect(find.byTooltip('Reopen task'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('task-done-${task.id}')));
    await tester.pumpAndSettle();

    final tasks = await fake.getTasks(listId: listId);
    expect(tasks.single.status, 'todo');
    expect(find.text('Done task'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Complete parent task?'), findsNothing);
    expect(find.text('Closed'), findsNothing);
    expect(find.byTooltip('Mark task done'), findsOneWidget);
  });

  testWidgets('nested task row checkbox toggles done todo done', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Parent task',
      dueAt: _todayStartMs(),
    );
    final child = await fake.createTask(
      listId: listId,
      title: 'Nested child task',
      parentTaskId: parent.id,
      dueAt: _todayStartMs(),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    final childCheckbox = find.byKey(ValueKey('task-done-${child.id}'));
    expect(find.text('Nested child task'), findsOneWidget);
    expect(tester.widget<Checkbox>(childCheckbox).onChanged, isNotNull);

    await tester.tap(childCheckbox);
    await tester.pumpAndSettle();
    var tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');

    await tester.tap(childCheckbox);
    await tester.pumpAndSettle();
    tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == child.id).status, 'todo');

    await tester.tap(childCheckbox);
    await tester.pumpAndSettle();
    tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');
    expect(tasks.singleWhere((task) => task.id == parent.id).status, 'todo');
  });

  testWidgets('open child under a closed parent remains toggleable', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Closed root',
      dueAt: _todayStartMs(),
    );
    final child = await fake.createTask(
      listId: listId,
      title: 'Open child under closed root',
      parentTaskId: parent.id,
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: parent.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    final childCheckbox = find.byKey(ValueKey('task-done-${child.id}'));
    expect(find.text('Open child under closed root'), findsOneWidget);
    expect(tester.widget<Checkbox>(childCheckbox).onChanged, isNotNull);

    await tester.tap(childCheckbox);
    await tester.pumpAndSettle();

    final tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');
    expect(find.text('Complete parent task?'), findsNothing);
  });

  testWidgets('wont_do root row leading control reopens without undo', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Skipped task',
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: task.id, status: 'wont_do');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Skipped task'), findsOneWidget);
    expect(find.byTooltip('Reopen task'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('task-done-${task.id}')));
    await tester.pumpAndSettle();

    final tasks = await fake.getTasks(listId: listId);
    expect(tasks.single.status, 'todo');
    expect(find.text('Skipped task'), findsOneWidget);
    expect(find.text("Won't do"), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Closed'), findsNothing);
    expect(find.byTooltip('Mark task done'), findsOneWidget);
  });

  testWidgets(
    'detail menu marks wont_do, reopens it, and hides invalid transitions',
    (tester) async {
      final fake = await _pumpAppWithSeedData(
        tester,
        listName: 'Inbox',
        taskTitle: 'Buy milk',
      );

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();

      expect(find.text('Mark done'), findsOneWidget);
      expect(find.text("Mark won't do"), findsOneWidget);
      expect(find.text('Reopen'), findsNothing);

      await tester.tap(find.text("Mark won't do"));
      await tester.pumpAndSettle();

      final listId = (await fake.getLists()).first.id;
      var active = await fake.getTasks(listId: listId);
      expect(active.single.status, 'wont_do');
      expect(find.text('Task closed.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text("Won't do"), findsOneWidget);

      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      expect(find.text('Reopen'), findsOneWidget);
      expect(find.text('Mark done'), findsNothing);
      expect(find.text("Mark won't do"), findsNothing);
      expect(find.text('In progress'), findsNothing);

      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();

      active = await fake.getTasks(listId: listId);
      expect(active.single.status, 'todo');
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      expect(find.text('Mark done'), findsOneWidget);
      expect(find.text("Mark won't do"), findsOneWidget);
    },
  );

  testWidgets('detail menu hides done to wont_do transition', (tester) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Done task',
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: task.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done task'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Task actions'));
    await tester.pumpAndSettle();

    expect(find.text('Reopen'), findsOneWidget);
    expect(find.text("Mark won't do"), findsNothing);
    expect(find.text('In progress'), findsNothing);
  });

  testWidgets('wont_do row is closed, struck through, and labeled', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final skipped = await fake.createTask(
      listId: listId,
      title: 'Skipped task',
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Skipped task'), findsOneWidget);
    expect(find.text("Won't do"), findsOneWidget);
    expect(find.byTooltip('Reopen task'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Skipped task'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('task list drag and drop reorders root tasks with boundaries', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final first = await fake.createTask(listId: listId, title: 'First task');
    final second = await fake.createTask(listId: listId, title: 'Second task');
    final third = await fake.createTask(listId: listId, title: 'Third task');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    _expectNoVisibleMoveButtons();
    expect(
      find.byKey(ValueKey('task-drop-target-${first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-drop-target-${second.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-drop-target-${third.id}')),
      findsOneWidget,
    );

    await _dragTaskOnto(
      tester,
      sourceTaskId: first.id,
      targetTaskId: third.id,
      dropAfterTarget: true,
    );
    await tester.pumpAndSettle();

    var active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), [second.id, third.id, first.id]);
    expect(fake.reorderCalls.last.taskId, first.id);
    expect(fake.reorderCalls.last.previousTaskId, third.id);
    expect(fake.reorderCalls.last.nextTaskId, isNull);

    await _dragTaskOnto(
      tester,
      sourceTaskId: first.id,
      targetTaskId: second.id,
      dropAfterTarget: false,
    );
    active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), [first.id, second.id, third.id]);
    expect(fake.reorderCalls.last.taskId, first.id);
    expect(fake.reorderCalls.last.previousTaskId, isNull);
    expect(fake.reorderCalls.last.nextTaskId, second.id);

    await _dragTaskOnto(
      tester,
      sourceTaskId: third.id,
      targetTaskId: second.id,
      dropAfterTarget: false,
    );
    active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), [first.id, third.id, second.id]);
    expect(fake.reorderCalls.last.taskId, third.id);
    expect(fake.reorderCalls.last.previousTaskId, first.id);
    expect(fake.reorderCalls.last.nextTaskId, second.id);

    _expectTaskTitleOrder(tester, ['First task', 'Third task', 'Second task']);
  });

  testWidgets(
    'task drag and drop rejects different parent and closed targets',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
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
      final root = await fake.createTask(listId: listId, title: 'Root task');
      final closed = await fake.createTask(
        listId: listId,
        title: 'Closed task',
      );
      await fake.setTaskStatus(taskId: closed.id, status: 'done');

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await _openListFromHome(tester, 'Inbox');

      await _dragTaskOnto(
        tester,
        sourceTaskId: root.id,
        targetTaskId: child.id,
        dropAfterTarget: false,
      );
      await _dragTaskOnto(
        tester,
        sourceTaskId: child.id,
        targetTaskId: root.id,
        dropAfterTarget: true,
      );

      expect(fake.reorderCalls, isEmpty);
      final tasks = await fake.getTasks(listId: listId);
      expect(
        tasks.where((task) => task.parentTaskId == null).map((task) => task.id),
        [parent.id, root.id, closed.id],
      );
      expect(
        tasks
            .where((task) => task.parentTaskId == parent.id)
            .map((task) => task.id),
        [child.id],
      );

      await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Closed task'), findsOneWidget);
      expect(
        find.byKey(ValueKey('task-drop-target-${closed.id}')),
        findsNothing,
      );
      _expectNoVisibleMoveButtons();
    },
  );

  testWidgets('task sort menu switches root order and drag targets', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final manualFirst = await fake.createTask(
      listId: listId,
      title: 'Manual first',
    );
    final manualSecond = await fake.createTask(
      listId: listId,
      title: 'Manual second',
    );
    final manualThird = await fake.createTask(
      listId: listId,
      title: 'Manual third',
    );
    final manualFourth = await fake.createTask(
      listId: listId,
      title: 'Manual fourth',
    );
    await fake.updateTask(
      taskId: manualFirst.id,
      title: manualFirst.title,
      note: '',
      priority: 1,
      dueAt: 300,
    );
    await fake.updateTask(
      taskId: manualSecond.id,
      title: manualSecond.title,
      note: '',
      priority: 3,
      dueAt: null,
    );
    await fake.updateTask(
      taskId: manualThird.id,
      title: manualThird.title,
      note: '',
      priority: 2,
      dueAt: 100,
    );
    await fake.updateTask(
      taskId: manualFourth.id,
      title: manualFourth.title,
      note: '',
      priority: 3,
      dueAt: 400,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    _expectTaskTitleOrder(tester, [
      'Manual first',
      'Manual second',
      'Manual third',
      'Manual fourth',
    ]);
    expect(find.byTooltip('Sort tasks'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-drop-target-${manualSecond.id}')),
      findsOneWidget,
    );
    _expectNoVisibleMoveButtons();

    await _selectTaskSortMode(tester, 'Due date');
    _expectTaskTitleOrder(tester, [
      'Manual third',
      'Manual first',
      'Manual fourth',
      'Manual second',
    ]);
    expect(
      find.byKey(ValueKey('task-drop-target-${manualSecond.id}')),
      findsNothing,
    );
    _expectNoVisibleMoveButtons();

    await _selectTaskSortMode(tester, 'Priority');
    _expectTaskTitleOrder(tester, [
      'Manual second',
      'Manual fourth',
      'Manual third',
      'Manual first',
    ]);

    await _selectTaskSortMode(tester, 'Created');
    _expectTaskTitleOrder(tester, [
      'Manual fourth',
      'Manual third',
      'Manual second',
      'Manual first',
    ]);

    await _selectTaskSortMode(tester, 'Manual');
    _expectTaskTitleOrder(tester, [
      'Manual first',
      'Manual second',
      'Manual third',
      'Manual fourth',
    ]);
    expect(
      find.byKey(ValueKey('task-drop-target-${manualSecond.id}')),
      findsOneWidget,
    );
    _expectNoVisibleMoveButtons();
  });

  testWidgets('task list keeps closed subtasks under their open parent', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(listId: listId, title: 'Plan launch');
    final child = await fake.createTask(
      listId: listId,
      title: 'Draft checklist',
      parentTaskId: parent.id,
    );
    final doneGrandchild = await fake.createTask(
      listId: listId,
      title: 'Review checklist',
      parentTaskId: child.id,
    );
    await fake.setTaskStatus(taskId: doneGrandchild.id, status: 'done');
    final wontDoChild = await fake.createTask(
      listId: listId,
      title: 'Skip launch microsite',
      parentTaskId: parent.id,
    );
    await fake.setTaskStatus(taskId: wontDoChild.id, status: 'wont_do');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    expect(find.text('Plan launch'), findsOneWidget);
    expect(find.text('Draft checklist'), findsOneWidget);
    expect(find.text('Review checklist'), findsOneWidget);
    expect(find.text('Skip launch microsite'), findsOneWidget);
    expect(find.text("Won't do"), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    expect(find.text('1/2'), findsNothing);
    expect(find.text('1/1'), findsNothing);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${child.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${doneGrandchild.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${wontDoChild.id}')),
      findsOneWidget,
    );

    final parentTop = tester.getTopLeft(find.text('Plan launch')).dy;
    final childTop = tester.getTopLeft(find.text('Draft checklist')).dy;
    final grandchildTop = tester.getTopLeft(find.text('Review checklist')).dy;
    final wontDoTop = tester.getTopLeft(find.text('Skip launch microsite')).dy;
    expect(parentTop, lessThan(childTop));
    expect(childTop, lessThan(grandchildTop));
    expect(parentTop, lessThan(wontDoTop));

    final doneTitle = tester.widget<Text>(find.text('Review checklist'));
    final wontDoTitle = tester.widget<Text>(find.text('Skip launch microsite'));
    expect(doneTitle.style?.decoration, TextDecoration.lineThrough);
    expect(wontDoTitle.style?.decoration, TextDecoration.lineThrough);
    expect(find.byTooltip('Reopen task'), findsNWidgets(2));
    expect(
      find.byKey(ValueKey('task-drop-target-${wontDoChild.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('task-drop-target-${child.id}')),
      findsOneWidget,
    );
    _expectNoVisibleMoveButtons();
  });

  testWidgets('hierarchy guides expose L and T branches aligned to checkbox', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(listId: listId, title: 'Parent');
    final branchChild = await fake.createTask(
      listId: listId,
      title: 'Branch child',
      parentTaskId: parent.id,
    );
    final grandchild = await fake.createTask(
      listId: listId,
      title: 'Grandchild',
      parentTaskId: branchChild.id,
    );
    final lastChild = await fake.createTask(
      listId: listId,
      title: 'Last child',
      parentTaskId: parent.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    final branchRow = tester.widget<AppTaskRow>(
      find.byKey(ValueKey('task-row-${branchChild.id}')),
    );
    final grandchildRow = tester.widget<AppTaskRow>(
      find.byKey(ValueKey('task-row-${grandchild.id}')),
    );
    final lastRow = tester.widget<AppTaskRow>(
      find.byKey(ValueKey('task-row-${lastChild.id}')),
    );

    expect(branchRow.depth, 1);
    expect(branchRow.isLastSibling, isFalse);
    expect(branchRow.ancestorLineContinuations, isEmpty);
    expect(grandchildRow.depth, 2);
    expect(grandchildRow.isLastSibling, isTrue);
    expect(grandchildRow.ancestorLineContinuations, [true]);
    expect(lastRow.depth, 1);
    expect(lastRow.isLastSibling, isTrue);

    final branchHorizontal = tester.getRect(
      find.byKey(ValueKey('task-hierarchy-horizontal-${branchChild.id}')),
    );
    final branchCheckboxCenter = tester.getCenter(
      find.byKey(ValueKey('task-done-${branchChild.id}')),
    );
    expect(branchHorizontal.center.dy, closeTo(branchCheckboxCenter.dy, 0.75));
  });

  testWidgets('closed parent moves its whole tree to root-based closed count', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final activeParent = await fake.createTask(
      listId: listId,
      title: 'Active parent',
    );
    final activeDoneChild = await fake.createTask(
      listId: listId,
      title: 'Done child under active parent',
      parentTaskId: activeParent.id,
    );
    await fake.setTaskStatus(taskId: activeDoneChild.id, status: 'done');
    final closedParent = await fake.createTask(
      listId: listId,
      title: 'Closed parent',
    );
    await fake.setTaskStatus(taskId: closedParent.id, status: 'done');
    final openChild = await fake.createTask(
      listId: listId,
      title: 'Open child under closed parent',
      parentTaskId: closedParent.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    expect(find.text('Active parent'), findsOneWidget);
    expect(find.text('Done child under active parent'), findsOneWidget);
    expect(find.text('Closed parent'), findsNothing);
    expect(find.text('Open child under closed parent'), findsNothing);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('1 closed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Closed parent'), findsOneWidget);
    expect(find.text('Open child under closed parent'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${openChild.id}')),
      findsOneWidget,
    );

    final closedParentTop = tester.getTopLeft(find.text('Closed parent')).dy;
    final openChildTop = tester
        .getTopLeft(find.text('Open child under closed parent'))
        .dy;
    expect(closedParentTop, lessThan(openChildTop));
  });

  testWidgets('condition sort keeps subtasks under their parent', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(listId: listId, title: 'Parent');
    final childLater = await fake.createTask(
      listId: listId,
      title: 'Child later',
      parentTaskId: parent.id,
    );
    final childSooner = await fake.createTask(
      listId: listId,
      title: 'Child sooner',
      parentTaskId: parent.id,
    );
    final otherRoot = await fake.createTask(
      listId: listId,
      title: 'Other root',
    );
    await fake.updateTask(
      taskId: childLater.id,
      title: childLater.title,
      note: '',
      priority: 0,
      dueAt: 300,
    );
    await fake.updateTask(
      taskId: childSooner.id,
      title: childSooner.title,
      note: '',
      priority: 0,
      dueAt: 100,
    );
    await fake.updateTask(
      taskId: otherRoot.id,
      title: otherRoot.title,
      note: '',
      priority: 0,
      dueAt: 50,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');
    await _selectTaskSortMode(tester, 'Due date');

    _expectTaskTitleOrder(tester, [
      'Other root',
      'Parent',
      'Child sooner',
      'Child later',
    ]);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${childSooner.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${childLater.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-drop-target-${childSooner.id}')),
      findsNothing,
    );
    _expectNoVisibleMoveButtons();
  });

  testWidgets('subtask semantics reorder keeps the same parent and depth', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
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
    await _openListFromHome(tester, 'Inbox');

    final semantics = tester.ensureSemantics();
    final firstChildSemantics = _reorderSemanticsFinder(
      'Move task down',
    ).evaluate().single;
    expect(
      _customActionLabels(firstChildSemantics),
      contains('Move task down'),
    );
    final secondChildSemantics = _reorderSemanticsFinder(
      'Move task up',
    ).evaluate().single;
    expect(_customActionLabels(secondChildSemantics), contains('Move task up'));
    tester.semantics.customAction(
      _reorderSemanticsFinder('Move task up'),
      const CustomSemanticsAction(label: 'Move task up'),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(fake.reorderCalls.last.taskId, secondChild.id);
    expect(fake.reorderCalls.last.previousTaskId, isNull);
    expect(fake.reorderCalls.last.nextTaskId, firstChild.id);

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
    'detail subtask checkbox toggles without triggering row navigation',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Parent detail task',
        dueAt: _todayStartMs(),
      );
      final child = await fake.createTask(
        listId: listId,
        title: 'Detail child task',
        parentTaskId: parent.id,
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parent detail task'));
      await tester.pumpAndSettle();

      final childCheckbox = find.byKey(ValueKey('task-done-${child.id}'));
      expect(find.text('Task detail'), findsOneWidget);
      expect(find.text('Parent detail task'), findsOneWidget);
      expect(find.text('Detail child task'), findsOneWidget);
      expect(tester.widget<Checkbox>(childCheckbox).onChanged, isNotNull);

      await tester.tap(childCheckbox);
      await tester.pumpAndSettle();

      var tasks = await fake.getTasks(listId: listId);
      expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');
      expect(find.text('Parent detail task'), findsOneWidget);
      expect(find.text('Task closed.'), findsOneWidget);

      await tester.tap(childCheckbox);
      await tester.pumpAndSettle();
      tasks = await fake.getTasks(listId: listId);
      expect(tasks.singleWhere((task) => task.id == child.id).status, 'todo');
      expect(find.text('Task closed.'), findsOneWidget);

      await tester.tap(find.text('Detail child task'));
      await tester.pumpAndSettle();
      final detailTitle = tester.widget<Text>(
        find.byKey(const ValueKey('task-title-inline-read-text')),
      );
      expect(detailTitle.data, 'Detail child task');
      expect(
        find.byKey(ValueKey('parent-task-link-${parent.id}')),
        findsOneWidget,
      );
    },
  );

  testWidgets('detail title checkbox marks an open task done', (tester) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Detail checkbox task',
    );

    await tester.tap(find.text('Detail checkbox task'));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    final task = (await fake.getTasks(listId: listId)).single;
    await tester.tap(find.byKey(ValueKey('task-detail-done-${task.id}')));
    await tester.pumpAndSettle();

    final tasks = await fake.getTasks(listId: listId);
    expect(tasks.single.status, 'done');
    expect(find.text('Task closed.'), findsOneWidget);
    expect(find.byTooltip('Reopen task'), findsOneWidget);

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('task-title-inline-read-text')),
    );
    final titleContext = tester.element(
      find.byKey(const ValueKey('task-title-inline-read-text')),
    );
    expect(title.style?.decoration, TextDecoration.lineThrough);
    expect(
      title.style?.color,
      Theme.of(titleContext).colorScheme.onSurfaceVariant,
    );
  });

  testWidgets('detail title checkbox reopens done and wont_do tasks', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final done = await fake.createTask(
      listId: listId,
      title: 'Done detail task',
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: done.id, status: 'done');
    final wontDo = await fake.createTask(
      listId: listId,
      title: 'Wont do detail task',
      dueAt: _todayStartMs(),
    );
    await fake.setTaskStatus(taskId: wontDo.id, status: 'wont_do');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done detail task'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-detail-done-${done.id}')));
    await tester.pumpAndSettle();

    var tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == done.id).status, 'todo');
    expect(find.text('Complete parent task?'), findsNothing);
    expect(find.text('Undo'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wont do detail task'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-detail-done-${wontDo.id}')));
    await tester.pumpAndSettle();

    tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == wontDo.id).status, 'todo');
    expect(find.text('Complete parent task?'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets(
    'detail title checkbox confirms before completing parent with open descendants',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Detail parent checkbox task',
        dueAt: _todayStartMs(),
      );
      await fake.createTask(
        listId: listId,
        title: 'Open child remains open',
        parentTaskId: parent.id,
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detail parent checkbox task'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('task-detail-done-${parent.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Complete parent task?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      var tasks = await fake.getTasks(listId: listId);
      expect(tasks.singleWhere((task) => task.id == parent.id).status, 'todo');

      await tester.tap(find.byKey(ValueKey('task-detail-done-${parent.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      tasks = await fake.getTasks(listId: listId);
      expect(tasks.singleWhere((task) => task.id == parent.id).status, 'done');
    },
  );

  testWidgets('detail parent link opens the immediate parent task', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final grandparent = await fake.createTask(
      listId: listId,
      title: 'Grandparent task',
      dueAt: _todayStartMs(),
    );
    final parent = await fake.createTask(
      listId: listId,
      title:
          'Immediate parent task with a title long enough to be ellipsized in the link row',
      parentTaskId: grandparent.id,
      dueAt: _todayStartMs(),
    );
    await fake.createTask(
      listId: listId,
      title: 'Child detail task',
      parentTaskId: parent.id,
      dueAt: _todayStartMs(),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child detail task'));
    await tester.pumpAndSettle();

    final parentLink = find.byKey(ValueKey('parent-task-link-${parent.id}'));
    expect(parentLink, findsOneWidget);
    expect(find.text('Grandparent task'), findsNothing);
    expect(tester.widget<Text>(parentLink).maxLines, 1);
    expect(tester.widget<Text>(parentLink).overflow, TextOverflow.ellipsis);

    await tester.tap(parentLink);
    await tester.pumpAndSettle();

    final detailTitle = tester.widget<Text>(
      find.byKey(const ValueKey('task-title-inline-read-text')),
    );
    expect(
      detailTitle.data,
      'Immediate parent task with a title long enough to be ellipsized in the link row',
    );
    expect(
      find.byKey(ValueKey('parent-task-link-${grandparent.id}')),
      findsOneWidget,
    );
    expect(find.textContaining('Immediate parent task'), findsOneWidget);
  });

  testWidgets('detail title and note right padding starts inline editing', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Short title',
      dueAt: _todayStartMs(),
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: 'Short note',
      priority: 0,
      dueAt: task.dueAt,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short title'));
    await tester.pumpAndSettle();

    final titleEditor = tester.getRect(
      find.byKey(ValueKey('task-title-editor-${task.id}')),
    );
    await tester.tapAt(Offset(titleEditor.right - 8, titleEditor.center.dy));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task-title-inline-field')),
      findsOneWidget,
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final noteEditor = tester.getRect(
      find.byKey(ValueKey('task-note-editor-${task.id}')),
    );
    await tester.tapAt(Offset(noteEditor.right - 8, noteEditor.center.dy));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task-note-inline-field')),
      findsOneWidget,
    );
  });

  testWidgets('detail subtasks show descendant tree with hierarchy guides', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Detail parent',
      dueAt: _todayStartMs(),
    );
    final branchChild = await fake.createTask(
      listId: listId,
      title: 'Detail branch child',
      parentTaskId: parent.id,
    );
    final grandchild = await fake.createTask(
      listId: listId,
      title: 'Detail grandchild',
      parentTaskId: branchChild.id,
    );
    final lastChild = await fake.createTask(
      listId: listId,
      title: 'Detail last child',
      parentTaskId: parent.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail parent'));
    await tester.pumpAndSettle();

    expect(find.text('Detail branch child'), findsOneWidget);
    expect(find.text('Detail grandchild'), findsOneWidget);
    expect(find.text('Detail last child'), findsOneWidget);

    final branchRow = tester.widget<AppTaskRow>(
      find.byKey(ValueKey('task-row-${branchChild.id}')),
    );
    final grandchildRow = tester.widget<AppTaskRow>(
      find.byKey(ValueKey('task-row-${grandchild.id}')),
    );
    final lastRow = tester.widget<AppTaskRow>(
      find.byKey(ValueKey('task-row-${lastChild.id}')),
    );
    expect(branchRow.depth, 1);
    expect(branchRow.isLastSibling, isFalse);
    expect(grandchildRow.depth, 2);
    expect(grandchildRow.ancestorLineContinuations, [true]);
    expect(lastRow.isLastSibling, isTrue);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${grandchild.id}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'incomplete descendants require confirmation before parent done',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Parent task',
        dueAt: _todayStartMs(),
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

  testWidgets(
    'incomplete descendants require confirmation before parent wont_do',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Parent task',
        dueAt: _todayStartMs(),
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
      await tester.tap(find.text('Parent task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Mark won't do"));
      await tester.pumpAndSettle();

      expect(find.text("Close parent as won't do?"), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      var active = await fake.getTasks(listId: listId);
      expect(active.singleWhere((task) => task.id == parent.id).status, 'todo');

      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Mark won't do"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      active = await fake.getTasks(listId: listId);
      expect(
        active.singleWhere((task) => task.id == parent.id).status,
        'wont_do',
      );
      expect(active.singleWhere((task) => task.id == child.id).status, 'todo');
    },
  );

  testWidgets('inline editing updates detail, list, and fake bridge state', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byTooltip('Task actions'), findsOneWidget);

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task-title-inline-field')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-title-inline-field')),
      'Buy oat milk',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task-note-inline-field')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-note-inline-field')),
      'Shelf-stable',
    );
    await tester.tap(find.text('Subtasks'));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    final task = (await fake.getTasks(listId: listId)).single;
    await tester.tap(find.byKey(ValueKey('task-priority-chip-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();

    expect(find.text('Buy oat milk'), findsOneWidget);
    expect(find.text('Shelf-stable'), findsOneWidget);
    expect(find.byTooltip('Priority: High'), findsOneWidget);

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

  testWidgets('inline title and note editing keep text offsets stable', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Stable inline title',
      dueAt: _todayStartMs(),
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: 'Stable inline note',
      priority: 0,
      dueAt: _todayStartMs(),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stable inline title'));
    await tester.pumpAndSettle();

    final titleReadOffset = tester.getTopLeft(
      find.byKey(const ValueKey('task-title-inline-read-text')),
    );
    await tester.tap(find.byKey(const ValueKey('task-title-inline-read-text')));
    await tester.pumpAndSettle();
    final titleFieldText = find.byKey(
      const ValueKey('task-title-inline-field'),
    );
    expect(titleFieldText, findsOneWidget);
    final titleEditOffset = tester.getTopLeft(titleFieldText);
    expect(titleEditOffset.dx, closeTo(titleReadOffset.dx, 0.1));
    expect(titleEditOffset.dy, closeTo(titleReadOffset.dy, 0.1));

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final noteReadOffset = tester.getTopLeft(
      find.byKey(const ValueKey('task-note-inline-read-text')),
    );
    await tester.tap(find.byKey(const ValueKey('task-note-inline-read-text')));
    await tester.pumpAndSettle();
    final noteFieldText = find.byKey(const ValueKey('task-note-inline-field'));
    expect(noteFieldText, findsOneWidget);
    final noteEditOffset = tester.getTopLeft(noteFieldText);
    expect(noteEditOffset.dx, closeTo(noteReadOffset.dx, 0.1));
    expect(noteEditOffset.dy, closeTo(noteReadOffset.dy, 0.1));
  });

  testWidgets('inline title editing shows undo and restores previous title', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-inline-field')),
      'Buy oat milk',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Task saved.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Undone.'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);

    final listId = (await fake.getLists()).first.id;
    final active = await fake.getTasks(listId: listId);
    expect(active.single.title, 'Buy milk');
  });

  testWidgets('undo snackbar disappears after four seconds', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    final checkboxFinder = find.byKey(const ValueKey('task-done-task-0'));
    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    expect(find.text('Task closed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Task closed.'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('undo action hides the undo snackbar before success', (
    tester,
  ) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-inline-field')),
      'Buy oat milk',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Task saved.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Task saved.'), findsNothing);
    expect(find.text('Undone.'), findsOneWidget);
  });

  testWidgets('empty inline title is discarded without saving', (tester) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-inline-field')),
      '   ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-title-inline-field')), findsNothing);
    expect(find.text('Buy milk'), findsWidgets);

    final listId = (await fake.getLists()).first.id;
    final active = await fake.getTasks(listId: listId);
    expect(active.single.title, 'Buy milk');
    expect(find.text('Task saved.'), findsNothing);
  });

  testWidgets('due date chip sets and clears due date immediately', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(listId: listId, title: 'Buy milk');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('task-due-chip-${task.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    var active = await fake.getTasks(listId: listId);
    expect(active.single.dueAt, isNotNull);
    expect(find.text('Task saved.'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('task-clear-due-${task.id}')));
    await tester.pumpAndSettle();

    active = await fake.getTasks(listId: listId);
    expect(active.single.dueAt, isNull);
    expect(find.text('No due date'), findsOneWidget);
  });

  testWidgets('task delete confirms irreversible deletion and removes task', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Task actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Delete task?'), findsOneWidget);
    expect(find.textContaining('permanently deleted'), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    expect(await fake.getTasks(listId: listId), isEmpty);
    expect(find.text('Buy milk'), findsNothing);
  });

  testWidgets('parent task delete warning includes descendant count', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Parent task',
      dueAt: _todayStartMs(),
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

    await tester.tap(find.text('Parent task'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Task actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('1 subtasks'), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    final active = await fake.getTasks(listId: listId);
    expect(active.map((task) => task.id), isNot(contains(parent.id)));
    expect(active.map((task) => task.id), isNot(contains(child.id)));
  });

  testWidgets(
    'delete action does not create undo while complete undo remains',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      await fake.createTask(
        listId: listId,
        title: 'Buy milk',
        dueAt: _todayStartMs(),
      );
      final next = await fake.createTask(
        listId: listId,
        title: 'Next task',
        dueAt: _todayStartMs(),
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect((await fake.getTasks(listId: listId)).map((task) => task.title), [
        'Next task',
      ]);
      expect(find.text('Undo'), findsNothing);
      expect(await fake.getLatestTaskUndo(), isNull);

      await tester.tap(find.byKey(ValueKey('task-done-${next.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Task closed.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    },
  );

  testWidgets('archived list task checkbox toggles like an active list', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final archived = await fake.createList(name: 'Archive me', sortOrder: 'a1');
    final task = await fake.createTask(
      listId: archived.id,
      title: 'Archived list task',
    );
    await fake.archiveList(listId: archived.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);
    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive me'));
    await tester.pumpAndSettle();

    final checkboxFinder = find.byKey(ValueKey('task-done-${task.id}'));
    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    var archivedTasks = await fake.getTasks(listId: archived.id);
    expect(
      archivedTasks.singleWhere((candidate) => candidate.id == task.id).status,
      'done',
    );
    expect(find.text('Archived list task'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    archivedTasks = await fake.getTasks(listId: archived.id);
    expect(
      archivedTasks.singleWhere((candidate) => candidate.id == task.id).status,
      'todo',
    );
    expect(find.text('Archived list task'), findsOneWidget);
    expect(find.text('Task closed.'), findsOneWidget);
  });
}
