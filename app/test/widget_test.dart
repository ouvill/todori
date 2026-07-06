import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';

import 'support/fake_bridge_service.dart';

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

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.byTooltip('Open lists'), findsOneWidget);
    expect(find.text('Add task'), findsOneWidget);

    await _openListFromHome(tester, 'Inbox');

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
    await _openListFromHome(tester, 'とても長い日本語のリスト名と English project name');

    expect(find.textContaining('四半期レビュー'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-priority-dot-${first.id}')),
      findsOneWidget,
    );
    expect(find.byTooltip('Move task up'), findsWidgets);
    expect(find.byTooltip('Move task down'), findsWidgets);
    expect(find.text('Local protection'), findsNothing);
    expect(tester.takeException(), isNull);

    final secondMoveUp = find.byKey(ValueKey('task-move-up-${second.id}'));
    // Scroll by hunting for the target rather than a fixed pixel delta: the
    // compact row layout (task-30) lets a very long wrapped title occupy
    // more vertical space than a fixed drag distance can predict.
    await tester.scrollUntilVisible(find.textContaining('Second task'), 220);
    await tester.pumpAndSettle();
    expect(find.textContaining('Second task'), findsOneWidget);
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

    expect(find.text('Start with a list.'), findsOneWidget);
    expect(
      find.text(
        'Create a list, then Todori will open straight into your tasks.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();

    expect(find.text('New list'), findsWidgets);
    expect(find.text('Create'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('polished list, sort, detail, and dialog surfaces stay stable', (
    tester,
  ) async {
    _useNarrowDynamicTypeView(tester);
    final fake = FakeBridgeService();
    await fake.createList(
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
    // Priority is conveyed by the dot + tooltip/semantics, not a text chip.
    expect(find.byTooltip('Priority: High'), findsOneWidget);
    final titleFinder = find.textContaining('README screenshot');
    final titleCenterY =
        (tester.getTopLeft(titleFinder).dy +
            tester.getBottomLeft(titleFinder).dy) /
        2;
    final dotCenterY = tester
        .getCenter(find.byKey(ValueKey('task-priority-dot-${task.id}')))
        .dy;
    expect(dotCenterY, closeTo(titleCenterY, 8));

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
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

  testWidgets('renaming the first list updates the fake bridge service', (
    tester,
  ) async {
    final fake = await _pumpAppWithSeedData(tester, listName: 'Inbox');

    await _openListsScreen(tester);
    await tester.tap(find.byTooltip('List actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Personal');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final lists = await fake.getLists();
    expect(lists.first.name, 'Personal');
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
  });

  testWidgets('rename dialog handles a long list name', (tester) async {
    _useNarrowDynamicTypeView(tester);
    const longListName = 'とても長い既定インボックス名 with a long English project label';
    await _pumpAppWithSeedData(tester, listName: longListName);

    await _openListsScreen(tester);
    await tester.tap(find.byTooltip('List actions').first);
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
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);

    await tester.tap(find.byTooltip('List actions').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect((await fake.getLists()).map((list) => list.name), ['Inbox']);
    expect((await fake.getArchivedLists()).map((list) => list.name), ['Work']);
    expect(find.text('Work'), findsNothing);
    expect(find.text('Archived (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Unarchive'), findsNothing);
  });

  testWidgets('unarchiving a list returns it to the active list section', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final work = await fake.createList(name: 'Work', sortOrder: 'a1');
    await fake.archiveList(listId: work.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);
    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('List actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unarchive'));
    await tester.pumpAndSettle();

    expect((await fake.getArchivedLists()), isEmpty);
    expect((await fake.getLists()).map((list) => list.name), ['Inbox', 'Work']);
    expect(find.text('Archived (1)'), findsNothing);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('default inbox does not expose archive action', (tester) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListsScreen(tester);

    await tester.tap(find.byTooltip('List actions').first);
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Archive'), findsNothing);
  });

  testWidgets('archived section is hidden when there are no archived lists', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
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
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
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
    expect(find.text('Task completed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('1 completed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(checkboxFinder, findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final undone = await fake.getTasks(listId: listId);
    expect(undone.single.status, 'todo');
    final undoneCheckbox = tester.widget<Checkbox>(checkboxFinder);
    expect(undoneCheckbox.value, isFalse);
    expect(find.text('Completed'), findsNothing);
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
    await _openListFromHome(tester, 'Inbox');

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

  testWidgets('task sort menu switches root order and move buttons', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
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
    expect(find.byTooltip('Move task up'), findsWidgets);

    await _selectTaskSortMode(tester, 'Due date');
    _expectTaskTitleOrder(tester, [
      'Manual third',
      'Manual first',
      'Manual fourth',
      'Manual second',
    ]);
    expect(find.byTooltip('Move task up'), findsNothing);
    expect(find.byTooltip('Move task down'), findsNothing);

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
    expect(find.byTooltip('Move task up'), findsWidgets);
  });

  testWidgets('task list shows subtasks without descendant progress badges', (
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
    await _openListFromHome(tester, 'Inbox');

    expect(find.text('Plan launch'), findsOneWidget);
    expect(find.text('Draft checklist'), findsOneWidget);
    expect(find.text('Review checklist'), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('1/2'), findsNothing);
    expect(find.text('1/1'), findsNothing);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${child.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${grandchild.id}')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Review checklist'), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${grandchild.id}')),
      findsNothing,
    );

    final parentTop = tester.getTopLeft(find.text('Plan launch')).dy;
    final childTop = tester.getTopLeft(find.text('Draft checklist')).dy;
    final grandchildTop = tester.getTopLeft(find.text('Review checklist')).dy;
    expect(parentTop, lessThan(childTop));
    expect(childTop, lessThan(grandchildTop));
  });

  testWidgets('condition sort keeps subtasks under their parent', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
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
    expect(find.byTooltip('Move task up'), findsNothing);
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
    await _openListFromHome(tester, 'Inbox');

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
    expect(find.byTooltip('Priority: High'), findsOneWidget);

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
    expect(find.textContaining('Deleted'), findsOneWidget);
    expect(find.textContaining('Deleted:'), findsNothing);
    expect(find.textContaining('1970'), findsNothing);
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
    await tester.tap(find.byTooltip('Open trash'));
    await tester.pumpAndSettle();

    expect(find.textContaining('削除済みでも復元'), findsOneWidget);
    expect(find.byTooltip('Priority: Medium'), findsOneWidget);
    expect(find.text('Priority: Medium'), findsNothing);
    expect(find.byTooltip('Restore task'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(ValueKey('restore-task-${task.id}')));
    await tester.pumpAndSettle();

    expect(await fake.getTrashedTasks(), isEmpty);
    expect(find.text('Trash is empty.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
