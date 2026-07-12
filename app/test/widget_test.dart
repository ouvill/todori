import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/core/task_due.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/screens/task_detail_screen.dart';
import 'package:todori/src/ui/task_components.dart';

import 'support/fake_bridge_service.dart';

const _taskCheckboxVisualCenterOffset = 24.0;
const _taskCheckboxVisualRadius = 11.0;
const _taskHierarchyHorizontalEndGap = 4.0;

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
    due: testDateOnlyDueFromMillis(_todayStartMs()),
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

void _useLocale(WidgetTester tester, Locale locale) {
  tester.platformDispatcher.localeTestValue = locale;
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

class _SlowCreateFakeBridgeService extends FakeBridgeService {
  final List<Completer<void>> _pendingCreates = [];

  int get pendingCreateCount => _pendingCreates.length;

  @override
  Future<TaskDto> createTask({
    required String listId,
    required String title,
    String? parentTaskId,
    Object? due,
    String note = '',
    int priority = 0,
    int? scheduledAt,
    int? estimatedMinutes,
  }) async {
    final completer = Completer<void>();
    _pendingCreates.add(completer);
    await completer.future;
    return super.createTask(
      listId: listId,
      title: title,
      parentTaskId: parentTaskId,
      due: due,
      note: note,
      priority: priority,
      scheduledAt: scheduledAt,
      estimatedMinutes: estimatedMinutes,
    );
  }

  void completeCreates() {
    for (final completer in _pendingCreates) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}

Future<void> _selectTaskSortMode(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Sort tasks'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openListsScreen(WidgetTester tester) async {
  await tester.tap(find.text('Lists').last);
  await tester.pumpAndSettle();
}

Future<void> _openListFromHome(WidgetTester tester, String listName) async {
  await _openListsScreen(tester);
  await tester.tap(find.text(listName).last);
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder finder, {
  double delta = 220,
}) async {
  if (finder.evaluate().isNotEmpty) {
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _ensureFinderVisible(
  WidgetTester tester,
  Finder finder, {
  double delta = 220,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder.first);
  }
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
  test(
    'date format helpers use locale skeletons and keep relative labels',
    () async {
      await initializeDateFormatting('ja');

      final sampleDate = DateTime(2026, 7, 8);
      expect(formatHomeHeaderDate('en', sampleDate), 'Wed, Jul 8');
      expect(formatHomeHeaderDate('ja', sampleDate), '7月8日(水)');

      final sampleEpochMs = sampleDate.millisecondsSinceEpoch;
      expect(formatAbsoluteDate('en', sampleEpochMs), 'Jul 8, 2026');
      expect(formatAbsoluteDate('ja', sampleEpochMs), '2026年7月8日');

      final en = lookupAppLocalizations(const Locale('en'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      expect(formatDueDate(en, dateOnlyDue(sampleDate)), 'Jul 8, 2026');
      expect(formatDueDate(ja, dateOnlyDue(sampleDate)), '2026年7月8日');

      final tomorrow = DateTime.now()
          .copyWith(
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
            microsecond: 0,
          )
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch;
      final tomorrowDue = testDateOnlyDueFromMillis(tomorrow);
      expect(
        formatRelativeDueDate(en, 'en', tomorrowDue),
        contains('Tomorrow'),
      );
      expect(formatRelativeDueDate(ja, 'ja', tomorrowDue), contains('明日'));
    },
  );

  testWidgets('home date heading follows the English platform locale', (
    tester,
  ) async {
    _useLocale(tester, const Locale('en'));
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(formatHomeHeaderDate('en', DateTime(2026, 7, 8)), 'Wed, Jul 8');
    expect(
      find.text(formatHomeHeaderDate('en', DateTime.now())),
      findsOneWidget,
    );
  });

  testWidgets('home date heading follows the Japanese platform locale', (
    tester,
  ) async {
    _useLocale(tester, const Locale('ja'));
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: '受信箱', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(formatHomeHeaderDate('ja', DateTime(2026, 7, 8)), '7月8日(水)');
    expect(
      find.text(formatHomeHeaderDate('ja', DateTime.now())),
      findsOneWidget,
    );
  });

  testWidgets('detail created at follows the Japanese platform locale', (
    tester,
  ) async {
    _useLocale(tester, const Locale('ja'));
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: '受信箱', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final task = await fake.createTask(
      listId: inbox.id,
      title: '作成日表示を確認する',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('作成日表示を確認する'));
    await tester.pumpAndSettle();

    expect(find.text('タスク詳細'), findsNothing);
    expect(
      find.text('作成日時: ${formatAbsoluteDate('ja', task.createdAt)}'),
      findsOneWidget,
    );
  });

  testWidgets('task detail shows a localized reminder chip', (tester) async {
    _useLocale(tester, const Locale('en'));
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final task = await fake.createTask(
      listId: inbox.id,
      title: 'Review reminder chip',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    final remindAt = DateTime(2026, 7, 8, 15, 30).millisecondsSinceEpoch;
    await fake.setTaskReminder(taskId: task.id, remindAt: remindAt);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review reminder chip'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('task-reminder-chip-${task.id}')),
      findsOneWidget,
    );
    expect(find.text(formatReminderDateTime('en', remindAt)), findsOneWidget);
    expect(find.byTooltip('Change reminder'), findsOneWidget);
    expect(find.byTooltip('Clear reminder'), findsOneWidget);
  });

  testWidgets('lists screen shows lists from the bridge service', (
    tester,
  ) async {
    await _pumpAppWithSeedData(tester, listName: 'Inbox');
    await _openListsScreen(tester);

    expect(find.text('Lists'), findsWidgets);
    expect(find.text('Inbox'), findsOneWidget);
  });

  testWidgets('top-level navigation uses a subtle vertical transition', (
    tester,
  ) async {
    await _pumpAppWithSeedData(tester, listName: 'Inbox');

    await tester.tap(find.text('Lists').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final slideOffsets = tester
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .map((transition) => transition.position.value.dy);
    expect(slideOffsets.any((dy) => dy > 0), isTrue);
  });

  testWidgets('tapping a list navigates to its task list', (tester) async {
    await _pumpAppWithSeedData(
      tester,
      listName: 'Inbox',
      taskTitle: 'Buy milk',
    );

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Lists'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-open')), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronRight300), findsNothing);

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
        due: testDateOnlyDueFromMillis(today),
      );
      final workOverdue = await fake.createTask(
        listId: work.id,
        title: 'Work overdue',
        due: testDateOnlyDueFromMillis(
          today - const Duration(days: 1).inMilliseconds,
        ),
      );
      await fake.createTask(listId: work.id, title: 'No due work');
      final scheduledToday = await fake.createTask(
        listId: work.id,
        title: 'Scheduled today only',
      );
      fake.setScheduledAtForTest(
        taskId: scheduledToday.id,
        scheduledAt: today + const Duration(hours: 12).inMilliseconds,
      );
      final scheduledTodayDueTomorrow = await fake.createTask(
        listId: work.id,
        title: 'Scheduled today due tomorrow',
        due: testDateOnlyDueFromMillis(tomorrow),
      );
      fake.setScheduledAtForTest(
        taskId: scheduledTodayDueTomorrow.id,
        scheduledAt: today + const Duration(hours: 13).inMilliseconds,
      );
      await fake.createTask(
        listId: work.id,
        title: 'Tomorrow work',
        due: testDateOnlyDueFromMillis(tomorrow),
      );
      await fake.createTask(
        listId: work.id,
        title: 'Upcoming work',
        due: testDateOnlyDueFromMillis(
          tomorrow + const Duration(days: 1).inMilliseconds,
        ),
      );
      await fake.createTask(
        listId: archived.id,
        title: 'Archived today',
        due: testDateOnlyDueFromMillis(today),
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Tomorrow'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-section-count-today')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-section-count-tomorrow')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await _scrollUntilVisible(tester, find.text('Work overdue'));
      expect(find.text('Work overdue'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(ValueKey('task-done-${workOverdue.id}')))
            .left,
        closeTo(tester.getTopLeft(find.text('Overdue')).dx, 0.75),
      );
      await _scrollUntilVisible(tester, find.text('Inbox due today'));
      expect(find.text('Inbox due today'), findsOneWidget);
      expect(find.text('Inbox'), findsOneWidget);
      await _scrollUntilVisible(tester, find.text('Scheduled today only'));
      expect(find.text('Scheduled today only'), findsOneWidget);
      await _scrollUntilVisible(
        tester,
        find.text('Scheduled today due tomorrow'),
      );
      expect(find.text('Scheduled today due tomorrow'), findsOneWidget);
      await _scrollUntilVisible(tester, find.text('Tomorrow work'));
      expect(find.text('Tomorrow work'), findsOneWidget);
      expect(find.text('Work'), findsWidgets);
      await _scrollUntilVisible(tester, find.text('Upcoming work'));
      expect(find.text('Upcoming work'), findsOneWidget);
      expect(find.text('No due work'), findsNothing);
      expect(find.text('Archived today'), findsNothing);
      expect(find.byTooltip('List actions'), findsNothing);
      expect(find.byTooltip('Move task up'), findsNothing);
      expect(find.byTooltip('Move task down'), findsNothing);
      expect(
        find.byKey(ValueKey('task-drop-target-${inboxDueToday.id}')),
        findsNothing,
      );

      await _scrollUntilVisible(
        tester,
        find.byTooltip('Sort tasks'),
        delta: -220,
      );
      await tester.tap(find.byTooltip('Sort tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Manual'), findsNothing);
      expect(find.text('Due date'), findsOneWidget);
      await tester.tap(find.text('Due date').last);
      await tester.pumpAndSettle();

      final tomorrowHeader = find.ancestor(
        of: find.byKey(const ValueKey('home-section-count-tomorrow')),
        matching: find.byType(InkWell),
      );
      await tester.tap(tomorrowHeader.first);
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow work'), findsNothing);
      await tester.tap(tomorrowHeader.first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Tomorrow work'));
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
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('New task'), findsNothing);
    expect(find.text('Create'), findsNothing);
    expect(find.byKey(const ValueKey('quick-add-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('task-create-title-field')),
      findsOneWidget,
    );
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    final listPropertyRect = tester.getRect(
      find.byKey(const ValueKey('task-create-list-property-row')),
    );
    final duePropertyRect = tester.getRect(
      find.byKey(const ValueKey('task-create-due-property-row')),
    );
    expect(listPropertyRect.height, greaterThanOrEqualTo(48));
    expect(duePropertyRect.height, greaterThanOrEqualTo(48));
    expect(duePropertyRect.top, greaterThanOrEqualTo(listPropertyRect.bottom));
    expect(duePropertyRect.width, listPropertyRect.width);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('task-create-submit')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('task-create-title-field')),
      'Today capture',
    );
    await tester.enterText(
      find.byKey(const ValueKey('task-create-note-field')),
      'Captured with context',
    );
    await tester.tap(find.byKey(const ValueKey('task-create-submit')));
    await tester.pumpAndSettle();

    final defaultList = (await fake.getLists()).singleWhere(
      (list) => list.isDefault,
    );
    final tasks = await fake.getTasks(listId: defaultList.id);
    expect(tasks.single.title, 'Today capture');
    expect(tasks.single.note, 'Captured with context');
    expect(
      taskDueCivilDate(tasks.single.due),
      civilDateFromLocal(DateTime.now()),
    );
    expect(find.text('Today capture'), findsOneWidget);
    expect(find.text('Inbox'), findsWidgets);
    expect(
      find.byKey(const ValueKey('task-create-title-field')),
      findsOneWidget,
    );
  });

  testWidgets('list create sheet creates in current list without due date', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await fake.createList(name: 'Work', sortOrder: 'a1');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Work');

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('New task'), findsNothing);
    expect(find.text('Create'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect(find.text('No due date'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('task-create-title-field')),
      'List capture',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-create-submit')));
    await tester.pumpAndSettle();

    final work = (await fake.getLists()).singleWhere(
      (list) => list.name == 'Work',
    );
    final tasks = await fake.getTasks(listId: work.id);
    expect(tasks.single.title, 'List capture');
    expect(tasks.single.due, isNull);
    expect(find.text('List capture'), findsOneWidget);
  });

  testWidgets('create sheet stores an exact deadline with IANA time zone', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-create-due-chip')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('task-create-due-pick-date-time')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-create-title-field')),
      'Exact deadline',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-create-submit')));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).single.id;
    final task = (await fake.getTasks(listId: listId)).single;
    expect(task.due, isA<TaskDueDto_DateTime>());
    expect(taskDueInstant(task.due), isNotNull);
    expect(taskDueSavedTimeZone(task.due), 'UTC');
    expect(taskDueCivilDate(task.due), isNull);
  });

  testWidgets(
    'create sheet ignores blanks and keeps focus for consecutive adds',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quick-add-open')));
      await tester.pumpAndSettle();
      final fieldFinder = find.byKey(const ValueKey('task-create-title-field'));
      await tester.enterText(fieldFinder, '   ');
      await tester.tap(find.byKey(const ValueKey('task-create-submit')));
      await tester.pumpAndSettle();

      final defaultList = (await fake.getLists()).singleWhere(
        (list) => list.isDefault,
      );
      expect(await fake.getTasks(listId: defaultList.id), isEmpty);

      await tester.enterText(fieldFinder, 'First capture');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      var field = tester.widget<TextField>(fieldFinder);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);

      await tester.enterText(fieldFinder, 'Second capture');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-create-submit')));
      await tester.pumpAndSettle();

      final tasks = await fake.getTasks(listId: defaultList.id);
      expect(tasks.map((task) => task.title), [
        'First capture',
        'Second capture',
      ]);
      field = tester.widget<TextField>(fieldFinder);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('create sheet submit ignores active composing range', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    final fieldFinder = find.byKey(const ValueKey('task-create-title-field'));
    await tester.tap(fieldFinder);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '変換中',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final defaultList = (await fake.getLists()).singleWhere(
      (list) => list.isDefault,
    );
    expect(await fake.getTasks(listId: defaultList.id), isEmpty);
  });

  testWidgets(
    'create sheet changes list and due, clears due, saves note, and keeps selections',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final work = await fake.createList(name: 'Work', sortOrder: 'a1');
      final today = _todayStartMs();
      final tomorrow = today + const Duration(days: 1).inMilliseconds;

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('quick-add-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-create-list-chip')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('task-create-list-option-${work.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Work'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('task-create-due-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-create-due-tomorrow')));
      await tester.pumpAndSettle();
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Tomorrow'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('task-create-title-field')),
        'Work tomorrow',
      );
      await tester.enterText(
        find.byKey(const ValueKey('task-create-note-field')),
        'Bring the outline',
      );
      await tester.tap(find.byKey(const ValueKey('task-create-submit')));
      await tester.pumpAndSettle();

      var workTasks = await fake.getTasks(listId: work.id);
      expect(workTasks.single.title, 'Work tomorrow');
      expect(workTasks.single.note, 'Bring the outline');
      expect(
        taskDueCivilDate(workTasks.single.due),
        civilDateFromLocal(DateTime.fromMillisecondsSinceEpoch(tomorrow)),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('task-create-title-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('task-create-note-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Work'), findsWidgets);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Tomorrow'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('task-create-due-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-create-due-pick-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-create-due-chip')));
      await tester.pumpAndSettle();
      final clearDue = find.byKey(const ValueKey('task-create-due-clear'));
      await tester.ensureVisible(clearDue);
      await tester.tap(clearDue);
      await tester.pumpAndSettle();
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('No due date'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('task-create-title-field')),
        'Work no due',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-create-submit')));
      await tester.pumpAndSettle();

      workTasks = await fake.getTasks(listId: work.id);
      expect(workTasks.map((task) => task.title), [
        'Work tomorrow',
        'Work no due',
      ]);
      expect(workTasks.last.due, isNull);
    },
  );

  testWidgets('create sheet disables add while submitting', (tester) async {
    final fake = _SlowCreateFakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-create-title-field')),
      'Slow capture',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-create-submit')));
    await tester.pump();
    expect(fake.pendingCreateCount, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('task-create-submit')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('task-create-submit')));
    await tester.pump();
    expect(fake.pendingCreateCount, 1);

    fake.completeCreates();
    await tester.pumpAndSettle();
    final defaultList = (await fake.getLists()).singleWhere(
      (list) => list.isDefault,
    );
    final tasks = await fake.getTasks(listId: defaultList.id);
    expect(tasks.single.title, 'Slow capture');
  });

  testWidgets(
    'capture persists typed due plan priority and retains all selections',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final work = await fake.createList(name: 'Work', sortOrder: 'a1');

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-add-open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('task-create-list-chip')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('task-create-list-option-${work.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-create-due-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-create-due-tomorrow')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('task-create-plan-property-row')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-start-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-25')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('plan-estimate-increase')));
      await tester.pump();
      expect(find.text('30 min'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-estimate-decrease')));
      await tester.pump();
      expect(find.text('25 min'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-45')));
      await tester.pump();
      expect(find.text('45 min'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-60')));
      await tester.pump();
      expect(find.text('60 min'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-45')));
      await tester.tap(find.byKey(const ValueKey('plan-apply')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('task-create-priority-property-row')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('priority-option-3')));
      await tester.pumpAndSettle();

      final title = find.byKey(const ValueKey('task-create-title-field'));
      await tester.enterText(title, 'First planned capture');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-create-submit')));
      await tester.pumpAndSettle();
      await tester.enterText(title, 'Second planned capture');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-create-submit')));
      await tester.pumpAndSettle();

      final tasks = await fake.getTasks(listId: work.id);
      expect(tasks.map((task) => task.title), [
        'First planned capture',
        'Second planned capture',
      ]);
      for (final task in tasks) {
        expect(task.due, isA<TaskDueDto_Date>());
        expect(task.scheduledAt, isNotNull);
        expect(task.estimatedMinutes, 45);
        expect(task.priority, 3);
      }
      expect(
        find.byKey(ValueKey('task-priority-dot-${tasks.last.id}')),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(
        find.semantics.byPredicate(
          (node) => node.getSemanticsData().label.contains('Priority, High'),
        ),
        findsWidgets,
      );
      semantics.dispose();

      await tester.tap(
        find.byKey(const ValueKey('task-create-plan-property-row')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Not planned'), findsWidgets);
    },
  );

  testWidgets('global navigation returns home and list actions stay ordered', (
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

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lists'), findsWidgets);
    expect(find.text('You'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Work')).dy,
      lessThan(tester.getTopLeft(find.text('New list')).dy),
    );
    expect(
      tester.getTopLeft(find.text('New list')).dy,
      lessThan(tester.getTopLeft(find.text('Archived (1)')).dy),
    );

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Lists'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-open')), findsOneWidget);
  });

  testWidgets('home shows standalone due subtask with parent context', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final today = _todayStartMs();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final parent = await fake.createTask(
      listId: inbox.id,
      title: 'Parent without due',
    );
    final child = await fake.createTask(
      listId: inbox.id,
      title: 'Due child only',
      parentTaskId: parent.id,
      due: testDateOnlyDueFromMillis(today),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Due child only'), findsOneWidget);
    expect(find.byKey(ValueKey('task-row-${parent.id}')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${child.id}')),
        matching: find.text('Parent without due'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${child.id}')),
        matching: find.text('Inbox'),
      ),
      findsNothing,
    );
    final semantics = tester.ensureSemantics();
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().label.contains(
          'Parent task: Parent without due',
        ),
      ),
      findsWidgets,
    );
    semantics.dispose();
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
  });

  testWidgets('home task rows expose meaningful semantics summaries', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final today = _todayStartMs();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final task = await fake.createTask(
      listId: inbox.id,
      title: 'Prepare accessibility notes',
      due: testDateOnlyDueFromMillis(today),
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: '',
      priority: 3,
      due: testDateOnlyDueFromMillis(today),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    expect(
      find.semantics.byPredicate((node) {
        final label = node.getSemanticsData().label;
        return label.contains('Prepare accessibility notes') &&
            label.contains('Status:') &&
            label.contains('Priority:') &&
            label.contains('Due:') &&
            label.contains('Double tap to open task');
      }),
      findsWidgets,
    );
    semantics.dispose();
  });

  testWidgets('task checkbox exposes button and checked semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTaskCheckbox(
            isDone: true,
            tooltip: 'Reopen task',
            onToggleDone: () {},
          ),
        ),
      ),
    );

    final semantics = tester.ensureSemantics();
    expect(
      find.semantics.byPredicate((node) {
        final data = node.getSemanticsData();
        return data.label.contains('Reopen task') &&
            data.flagsCollection.isButton &&
            data.flagsCollection.isChecked == CheckedState.isTrue;
      }),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('task creation sheet chips expose current semantic values', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    expect(
      find.semantics.byPredicate((node) {
        final data = node.getSemanticsData();
        return data.label.contains('Due: Today') &&
            data.flagsCollection.isButton;
      }),
      findsWidgets,
    );
    semantics.dispose();
  });

  testWidgets('home shows target subtrees with dedupe and interaction rules', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final today = _todayStartMs();
    final overdue = today - const Duration(days: 1).inMilliseconds;
    final tomorrow = today + const Duration(days: 1).inMilliseconds;
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final work = await fake.createList(name: 'Work', sortOrder: 'a1');
    final parent = await fake.createTask(
      listId: inbox.id,
      title: 'Home parent with children',
      due: testDateOnlyDueFromMillis(tomorrow),
    );
    final noDueChild = await fake.createTask(
      listId: inbox.id,
      title: 'No due child under home parent',
      parentTaskId: parent.id,
    );
    final sameSectionChild = await fake.createTask(
      listId: inbox.id,
      title: 'Same section child under home parent',
      parentTaskId: parent.id,
      due: testDateOnlyDueFromMillis(tomorrow),
    );
    final prunedGrandchild = await fake.createTask(
      listId: inbox.id,
      title: 'Grandchild under standalone child',
      parentTaskId: sameSectionChild.id,
    );
    final otherListChild = await fake.createTask(
      listId: work.id,
      title: 'Other list child under home parent',
      parentTaskId: parent.id,
    );
    final earlierChild = await fake.createTask(
      listId: inbox.id,
      title: 'Today child standalone',
      parentTaskId: parent.id,
      due: testDateOnlyDueFromMillis(today),
    );
    final overdueGrandchild = await fake.createTask(
      listId: inbox.id,
      title: 'Overdue grandchild standalone',
      parentTaskId: earlierChild.id,
      due: testDateOnlyDueFromMillis(overdue),
    );
    final closedChild = await fake.createTask(
      listId: inbox.id,
      title: 'Closed child under home parent',
      parentTaskId: parent.id,
    );
    await fake.setTaskStatus(taskId: closedChild.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('task-row-${parent.id}')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-count-today')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-count-overdue')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-count-tomorrow')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${overdueGrandchild.id}')),
    );
    expect(
      find.byKey(ValueKey('task-row-${overdueGrandchild.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-done-${overdueGrandchild.id}')),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${parent.id}')),
    );
    for (final task in [noDueChild, sameSectionChild, prunedGrandchild]) {
      await _scrollUntilVisible(
        tester,
        find.byKey(ValueKey('task-row-${task.id}')),
      );
      expect(find.byKey(ValueKey('task-row-${task.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('task-done-${task.id}')), findsOneWidget);
    }
    expect(find.text('No due date'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${noDueChild.id}')),
        matching: find.text('Inbox'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${otherListChild.id}')),
        matching: find.text('Work'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${sameSectionChild.id}')),
        matching: find.text('Home parent with children'),
      ),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${otherListChild.id}')),
    );
    for (final task in [otherListChild, closedChild]) {
      expect(find.byKey(ValueKey('task-row-${task.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('task-done-${task.id}')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${otherListChild.id}')),
        matching: find.text('Work'),
      ),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${earlierChild.id}')),
      delta: -220,
    );
    expect(find.byKey(ValueKey('task-row-${earlierChild.id}')), findsOneWidget);
    expect(
      find.byKey(ValueKey('task-done-${earlierChild.id}')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${earlierChild.id}')),
        matching: find.text('Home parent with children'),
      ),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${overdueGrandchild.id}')),
      delta: -220,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('task-row-${overdueGrandchild.id}')),
        matching: find.text('Today child standalone'),
      ),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${noDueChild.id}')),
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${noDueChild.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('task-drop-target-${noDueChild.id}')),
      findsNothing,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${sameSectionChild.id}')),
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${sameSectionChild.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('task-done-${sameSectionChild.id}')),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${prunedGrandchild.id}')),
    );
    expect(
      find.byKey(ValueKey('task-hierarchy-guide-${prunedGrandchild.id}')),
      findsOneWidget,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${closedChild.id}')),
    );
    expect(
      tester
          .widget<Text>(find.text('Closed child under home parent'))
          .style
          ?.decoration,
      TextDecoration.none,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${overdueGrandchild.id}')),
      delta: -220,
    );
    expect(
      find.byKey(ValueKey('task-done-${overdueGrandchild.id}')),
      findsOneWidget,
    );

    final semantics = tester.ensureSemantics();
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${sameSectionChild.id}')),
    );
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().label.contains(
          'Parent task: Home parent with children',
        ),
      ),
      findsWidgets,
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${overdueGrandchild.id}')),
      delta: -220,
    );
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().label.contains(
          'Parent task: Today child standalone',
        ),
      ),
      findsWidgets,
    );
    semantics.dispose();

    await _scrollUntilVisible(tester, find.text('Tomorrow'));
    await tester.tap(find.text('Tomorrow').first);
    await tester.pumpAndSettle();
    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-row-${earlierChild.id}')),
      delta: -220,
    );
    expect(find.byKey(ValueKey('task-row-${earlierChild.id}')), findsOneWidget);
    expect(find.text('No due child under home parent'), findsNothing);
    expect(find.byKey(ValueKey('task-row-${parent.id}')), findsNothing);
    await _scrollUntilVisible(
      tester,
      find.text('Overdue grandchild standalone'),
      delta: -220,
    );
    expect(find.text('Overdue grandchild standalone'), findsOneWidget);
    await _scrollUntilVisible(tester, find.text('Tomorrow'));
    await tester.tap(find.text('Tomorrow').first);
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('No due child under home parent'),
    );
    await tester.drag(
      find.byKey(ValueKey('task-row-${noDueChild.id}')),
      const Offset(-280, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-swipe-due-${noDueChild.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('due-sheet-tomorrow')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('due-sheet-tomorrow')));
    await tester.pumpAndSettle();
    final updatedNoDueChild = (await fake.getTasks(
      listId: inbox.id,
    )).singleWhere((task) => task.id == noDueChild.id);
    expect(
      taskDueCivilDate(updatedNoDueChild.due),
      civilDateFromLocal(
        DateTime.fromMillisecondsSinceEpoch(
          today + const Duration(days: 1).inMilliseconds,
        ),
      ),
    );

    await tester.ensureVisible(find.text('No due child under home parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-done-${noDueChild.id}')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.text('No due child under home parent'))
          .style
          ?.decoration,
      TextDecoration.none,
    );

    await tester.ensureVisible(find.text('No due child under home parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No due child under home parent'));
    await tester.pumpAndSettle();
    expect(find.text('Task detail'), findsNothing);
    expect(find.byTooltip('Task actions'), findsOneWidget);
    expect(find.text('No due child under home parent'), findsOneWidget);

    expect(sameSectionChild.parentTaskId, parent.id);
    expect(earlierChild.parentTaskId, parent.id);
  });

  testWidgets(
    'home nests closed due descendants under visible ancestors only',
    (tester) async {
      final fake = FakeBridgeService();
      final today = _todayStartMs();
      final overdue = today - const Duration(days: 1).inMilliseconds;
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final inbox = (await fake.getLists()).singleWhere(
        (list) => list.isDefault,
      );
      final hiddenRoot = await fake.createTask(
        listId: inbox.id,
        title: 'Hidden root without due',
      );
      final todayChild = await fake.createTask(
        listId: inbox.id,
        title: 'Today parent subtask',
        parentTaskId: hiddenRoot.id,
        due: testDateOnlyDueFromMillis(today),
      );
      final closedOverdueGrandchild = await fake.createTask(
        listId: inbox.id,
        title: 'Closed overdue grandchild',
        parentTaskId: todayChild.id,
        due: testDateOnlyDueFromMillis(overdue),
      );
      await fake.setTaskStatus(
        taskId: closedOverdueGrandchild.id,
        status: 'done',
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('task-row-${hiddenRoot.id}')), findsNothing);
      expect(find.byKey(ValueKey('task-row-${todayChild.id}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('task-row-${closedOverdueGrandchild.id}')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-section-count-overdue')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-section-count-today')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.text('Closed overdue grandchild'))
            .style
            ?.decoration,
        TextDecoration.none,
      );
      expect(
        find.byKey(
          ValueKey('task-hierarchy-guide-${closedOverdueGrandchild.id}'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Closed overdue grandchild')).dy,
        greaterThan(tester.getTopLeft(find.text('Today parent subtask')).dy),
      );
      final overdueLabel = DateFormat.MMMd(
        'en',
      ).format(DateTime.fromMillisecondsSinceEpoch(overdue).toLocal());
      final closedDuePillText = find.descendant(
        of: find.byKey(ValueKey('task-row-${closedOverdueGrandchild.id}')),
        matching: find.text(overdueLabel),
      );
      expect(closedDuePillText, findsOneWidget);
      final colorScheme = Theme.of(
        tester.element(closedDuePillText),
      ).colorScheme;
      expect(
        tester.widget<Text>(closedDuePillText).style?.color,
        colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
      );
      final closedDuePillBackgrounds = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: closedDuePillText,
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.color);
      expect(closedDuePillBackgrounds, isEmpty);

      await tester.tap(find.text('Today').first);
      await tester.pumpAndSettle();
      expect(find.text('Today parent subtask'), findsNothing);
      expect(find.text('Closed overdue grandchild'), findsNothing);
    },
  );

  testWidgets('home routes closed roots to Closed instead of date sections', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final today = _todayStartMs();
    final overdue = today - const Duration(days: 1).inMilliseconds;
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final closedRoot = await fake.createTask(
      listId: inbox.id,
      title: 'Closed overdue root',
      due: testDateOnlyDueFromMillis(overdue),
    );
    await fake.setTaskStatus(taskId: closedRoot.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-count-overdue')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Closed overdue root'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Closed overdue root'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Closed overdue root')).style?.decoration,
      TextDecoration.none,
    );
  });

  testWidgets('home hides closed subtasks without a visible ancestor', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final today = _todayStartMs();
    final overdue = today - const Duration(days: 1).inMilliseconds;
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final inbox = (await fake.getLists()).singleWhere((list) => list.isDefault);
    final hiddenRoot = await fake.createTask(
      listId: inbox.id,
      title: 'No due ancestor',
    );
    final closedChild = await fake.createTask(
      listId: inbox.id,
      title: 'Closed child without home ancestor',
      parentTaskId: hiddenRoot.id,
      due: testDateOnlyDueFromMillis(overdue),
    );
    await fake.setTaskStatus(taskId: closedChild.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No due ancestor'), findsNothing);
    expect(find.text('Closed child without home ancestor'), findsNothing);
    expect(find.text('Closed'), findsNothing);
    expect(find.text('A little room to breathe.'), findsOneWidget);
  });

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
      due: testDateOnlyDueFromMillis(1),
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

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
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
    'default inbox empty tasks and quick add survive narrow Dynamic Type',
    (tester) async {
      _useNarrowDynamicTypeView(tester);
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('A little room to breathe.'), findsOneWidget);
      expect(find.text('Add task'), findsNothing);
      expect(find.byKey(const ValueKey('quick-add-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-field')), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const ValueKey('quick-add-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-add-open')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('task-create-title-field')),
        findsOneWidget,
      );
      expect(find.text('New task'), findsNothing);
      expect(find.text('Create'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('capture planning stays reachable at 320px Japanese text 2.0', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    _useLocale(tester, const Locale('ja'));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: '受信箱', sortOrder: 'a0');
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    final planRow = find.byKey(const ValueKey('task-create-plan-property-row'));
    await _ensureFinderVisible(tester, planRow, delta: 120);
    await tester.tap(planRow);
    await tester.pumpAndSettle();
    await _ensureFinderVisible(
      tester,
      find.byKey(const ValueKey('plan-estimate-preset-60')),
      delta: 100,
    );
    expect(
      find.byKey(const ValueKey('plan-estimate-preset-25')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('plan-estimate-preset-45')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('plan-estimate-preset-60')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('plan-clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-apply')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan controls remain reachable in RTL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Scaffold(
          body: TaskPlanSheet(initialValue: TaskPlanValue()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-estimate-increase')));
    await tester.pump();
    expect(find.text('5 min'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-estimate-decrease')));
    await tester.pump();
    expect(find.text('No estimate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      due: testDateOnlyDueFromMillis(1),
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

    expect(find.text('Task detail'), findsNothing);
    expect(find.textContaining('長いnoteでも詳細画面'), findsOneWidget);
    // Priority is conveyed by the editable property row and its small dot,
    // not beside the title or via the removed edit dialog.
    final priorityRow = find.byKey(ValueKey('task-priority-chip-${task.id}'));
    await _ensureFinderVisible(tester, priorityRow);
    expect(priorityRow, findsOneWidget);
    final titleFinder = find.textContaining('README screenshot');
    final titleBottomY = tester.getBottomLeft(titleFinder).dy;
    final dotCenterY = tester
        .getCenter(find.byKey(ValueKey('task-priority-dot-${task.id}')))
        .dy;
    expect(dotCenterY, greaterThan(titleBottomY));

    expect(find.byIcon(LucideIcons.squarePen300), findsNothing);
    await _ensureFinderVisible(tester, titleFinder);
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

    expect(find.text('Task detail'), findsNothing);
    expect(find.text('Buy milk'), findsOneWidget);
    // No persistent Local protection/lock chip in the main task UI (see
    // `docs/design/visual-direction.md` Security Signal section); status
    // keeps a short, unprefixed pill in the detail header.
    expect(find.text('Local protection'), findsNothing);
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Lists'), findsNothing);
    expect(find.text('You'), findsNothing);
    expect(find.byKey(const ValueKey('quick-add-open')), findsNothing);
  });

  testWidgets(
    'detail plan and priority update and clear preserve core fields',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).single.id;
      final due = testDateOnlyDueFromMillis(_todayStartMs());
      final task = await fake.createTask(
        listId: listId,
        title: 'Keep the brief intact',
        note: 'Planning metadata must not erase this note',
        due: due,
        scheduledAt: _todayStartMs() + const Duration(hours: 10).inMilliseconds,
        estimatedMinutes: 25,
        priority: 1,
      );
      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep the brief intact'));
      await tester.pumpAndSettle();

      final planRow = find.byKey(ValueKey('task-plan-row-${task.id}'));
      await _ensureFinderVisible(tester, planRow);
      await tester.tap(planRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-60')));
      await tester.tap(find.byKey(const ValueKey('plan-apply')));
      await tester.pumpAndSettle();

      final priorityRow = find.byKey(ValueKey('task-priority-chip-${task.id}'));
      await _ensureFinderVisible(tester, priorityRow);
      await tester.tap(priorityRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('priority-option-3')));
      await tester.pumpAndSettle();

      var updated = (await fake.getTasks(listId: listId)).single;
      expect(updated.title, task.title);
      expect(updated.note, task.note);
      expect(taskDueCivilDate(updated.due), taskDueCivilDate(due));
      expect(updated.scheduledAt, task.scheduledAt);
      expect(updated.estimatedMinutes, 60);
      expect(updated.priority, 3);

      await _ensureFinderVisible(tester, planRow);
      await tester.tap(planRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-clear')));
      await tester.pumpAndSettle();
      await _ensureFinderVisible(tester, priorityRow);
      await tester.tap(priorityRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('priority-option-0')));
      await tester.pumpAndSettle();

      updated = (await fake.getTasks(listId: listId)).single;
      expect(updated.title, task.title);
      expect(updated.note, task.note);
      expect(taskDueCivilDate(updated.due), taskDueCivilDate(due));
      expect(updated.scheduledAt, isNull);
      expect(updated.estimatedMinutes, isNull);
      expect(updated.priority, 0);
    },
  );

  testWidgets('detail scheduled clear invalidates the Home smart view', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Scheduled only task',
      scheduledAt: _todayStartMs() + const Duration(hours: 9).inMilliseconds,
      estimatedMinutes: 25,
    );
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scheduled only task'), findsOneWidget);
    await tester.tap(find.text('Scheduled only task'));
    await tester.pumpAndSettle();

    final planRow = find.byKey(ValueKey('task-plan-row-${task.id}'));
    await _ensureFinderVisible(tester, planRow);
    await tester.tap(planRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-clear')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Scheduled only task'), findsNothing);
    final updated = (await fake.getTasks(listId: listId)).single;
    expect(updated.scheduledAt, isNull);
    expect(updated.estimatedMinutes, isNull);
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
    expect(find.byIcon(LucideIcons.chevronRight300), findsNothing);
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
      await tester.enterText(find.byType(TextField).last, 'Personal');
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

    final textField = tester.widget<TextField>(find.byType(TextField).last);
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
    expect(find.byIcon(LucideIcons.chevronDown300), findsOneWidget);

    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronUp300), findsOneWidget);
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
    expect(checkboxFinder, findsOneWidget);
    expect(find.byTooltip('Mark task done'), findsOneWidget);

    await tester.tap(checkboxFinder);
    await tester.pump(const Duration(milliseconds: 125));
    await tester.pump(const Duration(milliseconds: 125));

    final active = await fake.getTasks(listId: listId);
    expect(active.single.status, 'done');
    expect(find.text('Task closed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Buy milk'), findsNothing);
    expect(find.text('Closed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 75));
    await tester.pumpAndSettle();

    final undone = await fake.getTasks(listId: listId);
    expect(undone.single.status, 'todo');
    expect(checkboxFinder, findsOneWidget);
    expect(find.byTooltip('Mark task done'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
  });

  testWidgets('list completion invalidates the Home smart view', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Complete from Inbox',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Complete from Inbox'), findsOneWidget);

    await _openListFromHome(tester, 'Inbox');
    await tester.tap(find.byKey(ValueKey('task-done-${task.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();

    expect(find.text('Complete from Inbox'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('completion motion exposes intermediate halo and strike frame', (
    tester,
  ) async {
    var isDone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final style = Theme.of(context).textTheme.titleMedium;
                return Center(
                  child: SizedBox(
                    width: 180,
                    child: Row(
                      children: [
                        AppTaskCheckbox(
                          checkboxKey: const ValueKey('motion-checkbox'),
                          isDone: isDone,
                          tooltip: 'Toggle motion task',
                          onToggleDone: () => setState(() => isDone = !isDone),
                        ),
                        Expanded(
                          child: AppAnimatedTaskTitle(
                            'Motion title wraps to a second line',
                            isDone: isDone,
                            maxLines: 2,
                            style: style?.copyWith(
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task-completion-halo')), findsNothing);
    expect(
      find.byKey(const ValueKey('task-strikethrough-overlay')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('motion-checkbox')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const ValueKey('task-completion-halo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-strikethrough-overlay')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    final completedTitle = tester.widget<Text>(
      find.text('Motion title wraps to a second line'),
    );
    expect(completedTitle.style?.decoration, TextDecoration.none);
    expect(
      find.byKey(const ValueKey('task-strikethrough-overlay')),
      findsOneWidget,
    );
  });

  testWidgets('completion motion is skipped when reduce motion is enabled', (
    tester,
  ) async {
    var isDone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final style = Theme.of(context).textTheme.titleMedium;
                return Center(
                  child: Row(
                    children: [
                      AppTaskCheckbox(
                        checkboxKey: const ValueKey('reduce-motion-checkbox'),
                        isDone: isDone,
                        tooltip: 'Toggle reduce motion task',
                        onToggleDone: () => setState(() => isDone = !isDone),
                      ),
                      Expanded(
                        child: AppAnimatedTaskTitle(
                          'Reduce motion title',
                          isDone: isDone,
                          style: style?.copyWith(
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('reduce-motion-checkbox')));
    await tester.pump();

    expect(find.byKey(const ValueKey('task-completion-halo')), findsNothing);
    expect(
      find.byKey(const ValueKey('task-strikethrough-overlay')),
      findsOneWidget,
    );
    final completedTitle = tester.widget<Text>(
      find.text('Reduce motion title'),
    );
    expect(completedTitle.style?.decoration, TextDecoration.none);
  });

  testWidgets('task checkbox keeps 48px hit area centered on visual mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppTaskCheckbox(
              checkboxKey: const ValueKey('geometry-checkbox'),
              isDone: false,
              tooltip: 'Toggle geometry task',
              onToggleDone: () {},
            ),
          ),
        ),
      ),
    );

    final checkbox = find.byKey(const ValueKey('geometry-checkbox'));
    final checkboxRect = tester.getRect(checkbox);
    final markRect = tester.getRect(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.size == const Size.square(22),
          )
          .first,
    );

    expect(checkboxRect.size, const Size.square(48));
    expect(markRect.size, const Size.square(22));
    expect(markRect.center.dx, closeTo(checkboxRect.center.dx, 0.001));
    expect(markRect.center.dy, closeTo(checkboxRect.center.dy, 0.001));
  });

  testWidgets('home completion keeps standalone root until delayed exit', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Root due today pending exit',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    final checkboxFinder = find.byKey(ValueKey('task-done-${task.id}'));
    final checkboxStateBefore = tester.state(
      find.ancestor(of: checkboxFinder, matching: find.byType(AppTaskCheckbox)),
    );

    await tester.tap(checkboxFinder);
    await tester.pump();
    final checkboxStateAfter = tester.state(
      find.ancestor(of: checkboxFinder, matching: find.byType(AppTaskCheckbox)),
    );
    expect(identical(checkboxStateBefore, checkboxStateAfter), isTrue);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Root due today pending exit'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    expect(find.byKey(const ValueKey('task-completion-halo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-strikethrough-overlay')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 449));
    expect(find.text('Root due today pending exit'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2));
    expect(
      find.byKey(const ValueKey('home-pending-completion-exit')),
      findsOneWidget,
    );
    expect(find.text('Root due today pending exit'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 420));
    expect(find.text('Root due today pending exit'), findsNothing);
    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('home completion keeps visible subtree until delayed exit', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Pending subtree parent',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    final child = await fake.createTask(
      listId: listId,
      title: 'Pending subtree child',
      parentTaskId: parent.id,
    );
    final grandchild = await fake.createTask(
      listId: listId,
      title: 'Pending subtree grandchild',
      parentTaskId: child.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    State<StatefulWidget> checkboxStateFor(String taskId) {
      return tester.state<State<StatefulWidget>>(
        find.ancestor(
          of: find.byKey(ValueKey('task-done-$taskId')),
          matching: find.byType(AppTaskCheckbox),
        ),
      );
    }

    final parentStateBefore = checkboxStateFor(parent.id);
    final childStateBefore = checkboxStateFor(child.id);
    final grandchildStateBefore = checkboxStateFor(grandchild.id);

    await tester.tap(find.byKey(ValueKey('task-done-${parent.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(identical(parentStateBefore, checkboxStateFor(parent.id)), isTrue);
    expect(identical(childStateBefore, checkboxStateFor(child.id)), isTrue);
    expect(
      identical(grandchildStateBefore, checkboxStateFor(grandchild.id)),
      isTrue,
    );
    expect(find.text('Pending subtree parent'), findsOneWidget);
    expect(find.text('Pending subtree child'), findsOneWidget);
    expect(find.text('Pending subtree grandchild'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-completion-halo')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 449));
    expect(find.text('Pending subtree parent'), findsOneWidget);
    expect(find.text('Pending subtree child'), findsOneWidget);
    expect(find.text('Pending subtree grandchild'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    expect(
      find.byKey(const ValueKey('home-pending-completion-exit')),
      findsOneWidget,
    );
    expect(find.text('Pending subtree parent'), findsOneWidget);
    expect(find.text('Pending subtree child'), findsOneWidget);
    expect(find.text('Pending subtree grandchild'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 420));
    await tester.pumpAndSettle();
    expect(find.text('Pending subtree parent'), findsNothing);
    expect(find.text('Pending subtree child'), findsNothing);
    expect(find.text('Pending subtree grandchild'), findsNothing);
    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets(
    'home completion keeps standalone subtask before moving under ancestor',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final today = _todayStartMs();
      final tomorrow = today + const Duration(days: 1).inMilliseconds;
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Parent due tomorrow',
        due: testDateOnlyDueFromMillis(tomorrow),
      );
      final child = await fake.createTask(
        listId: listId,
        title: 'Child due today moves',
        parentTaskId: parent.id,
        due: testDateOnlyDueFromMillis(today),
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('task-done-${child.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Child due today moves'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Child due today moves')).dy,
        lessThan(tester.getTopLeft(find.text('Tomorrow').first).dy),
      );
      expect(
        find.byKey(const ValueKey('home-pending-completion-exit')),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 1020));

      expect(find.text('Child due today moves'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Child due today moves')).dy,
        greaterThan(tester.getTopLeft(find.text('Parent due tomorrow')).dy),
      );
    },
  );

  testWidgets(
    'home accompanied subtask completes in place without exit remount',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final parent = await fake.createTask(
        listId: listId,
        title: 'Visible parent today',
        due: testDateOnlyDueFromMillis(_todayStartMs()),
      );
      final child = await fake.createTask(
        listId: listId,
        title: 'Accompanied child no due',
        parentTaskId: parent.id,
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      final checkboxFinder = find.byKey(ValueKey('task-done-${child.id}'));
      final checkboxStateBefore = tester.state(
        find.ancestor(
          of: checkboxFinder,
          matching: find.byType(AppTaskCheckbox),
        ),
      );
      final rowTopBefore = tester
          .getTopLeft(find.byKey(ValueKey('task-row-${child.id}')))
          .dy;

      await tester.tap(checkboxFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final checkboxStateAfter = tester.state(
        find.ancestor(
          of: checkboxFinder,
          matching: find.byType(AppTaskCheckbox),
        ),
      );
      final rowTopAfter = tester
          .getTopLeft(find.byKey(ValueKey('task-row-${child.id}')))
          .dy;
      final tasks = await fake.getTasks(listId: listId);

      expect(identical(checkboxStateBefore, checkboxStateAfter), isTrue);
      expect(rowTopAfter, closeTo(rowTopBefore, 0.001));
      expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');
      expect(
        find.byKey(const ValueKey('home-pending-completion-exit')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('task-completion-halo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('task-strikethrough-overlay')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text('Accompanied child no due'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-pending-completion-exit')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.byKey(ValueKey('task-row-${child.id}'))).dy,
        closeTo(rowTopBefore, 0.001),
      );
    },
  );

  testWidgets(
    'home completion pending state handles multi-complete and reopen',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final first = await fake.createTask(
        listId: listId,
        title: 'First pending reopen',
        due: testDateOnlyDueFromMillis(_todayStartMs()),
      );
      final second = await fake.createTask(
        listId: listId,
        title: 'Second pending complete',
        due: testDateOnlyDueFromMillis(_todayStartMs()),
      );

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('task-done-${first.id}')));
      await tester.tap(find.byKey(ValueKey('task-done-${second.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('First pending reopen'), findsOneWidget);
      expect(find.text('Second pending complete'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('task-done-${first.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      final tasks = await fake.getTasks(listId: listId);
      expect(tasks.singleWhere((task) => task.id == first.id).status, 'todo');
      expect(tasks.singleWhere((task) => task.id == second.id).status, 'done');
      expect(find.text('First pending reopen'), findsOneWidget);
      expect(find.text('Second pending complete'), findsNothing);
    },
  );

  testWidgets('home reduce motion completion reconfigures immediately', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Reduce motion home task',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('task-done-${task.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('home-pending-completion-exit')),
      findsNothing,
    );
    expect(find.text('Reduce motion home task'), findsNothing);
    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('leading swipe completes through confirmation and undo flow', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Parent swipe task',
    );
    await fake.createTask(
      listId: listId,
      title: 'Open child task',
      parentTaskId: parent.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _openListFromHome(tester, 'Inbox');

    await tester.drag(
      find.byKey(ValueKey('task-row-${parent.id}')),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-swipe-leading-${parent.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Complete parent task?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    var tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == parent.id).status, 'done');
    expect(find.text('Task closed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == parent.id).status, 'todo');
  });

  testWidgets(
    'trailing swipe opens due sheet and updates today tomorrow and picked date',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).first.id;
      final task = await fake.createTask(listId: listId, title: 'Swipe due');
      final today = _todayStartMs();
      final tomorrow = today + const Duration(days: 1).inMilliseconds;

      await tester.pumpWidget(
        TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
      );
      await tester.pumpAndSettle();
      await _openListFromHome(tester, 'Inbox');

      await tester.drag(
        find.byKey(ValueKey('task-row-${task.id}')),
        const Offset(-280, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('task-swipe-due-${task.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Due'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('due-sheet-today')));
      await tester.pumpAndSettle();
      var tasks = await fake.getTasks(listId: listId);
      expect(
        taskDueCivilDate(tasks.single.due),
        civilDateFromLocal(DateTime.fromMillisecondsSinceEpoch(today)),
      );

      await tester.drag(
        find.byKey(ValueKey('task-row-${task.id}')),
        const Offset(-280, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('task-swipe-due-${task.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('due-sheet-tomorrow')));
      await tester.pumpAndSettle();
      tasks = await fake.getTasks(listId: listId);
      expect(
        taskDueCivilDate(tasks.single.due),
        civilDateFromLocal(DateTime.fromMillisecondsSinceEpoch(tomorrow)),
      );

      await tester.drag(
        find.byKey(ValueKey('task-row-${task.id}')),
        const Offset(-280, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('task-swipe-due-${task.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('due-sheet-pick-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      tasks = await fake.getTasks(listId: listId);
      expect(taskDueCivilDate(tasks.single.due), isNotNull);
      expect(find.text('Task saved.'), findsOneWidget);
    },
  );

  testWidgets('home due swipe moves a task into the tomorrow section', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Home today task',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(ValueKey('task-row-${task.id}')),
      const Offset(-280, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-swipe-due-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('due-sheet-tomorrow')));
    await tester.pumpAndSettle();

    final tasks = await fake.getTasks(listId: listId);
    expect(
      taskDueCivilDate(tasks.single.due),
      civilDateFromLocal(DateTime.now().add(const Duration(days: 1))),
    );
    expect(
      tester.getTopLeft(find.text('Home today task')).dy,
      greaterThan(tester.getTopLeft(find.text('Tomorrow').first).dy),
    );
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.setTaskStatus(taskId: task.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Done task'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Done task'), findsOneWidget);
    expect(find.byTooltip('Reopen task'), findsOneWidget);

    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-done-${task.id}')),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    final child = await fake.createTask(
      listId: listId,
      title: 'Nested child task',
      parentTaskId: parent.id,
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    final childCheckbox = find.byKey(ValueKey('task-done-${child.id}'));
    expect(find.text('Nested child task'), findsOneWidget);
    expect(childCheckbox, findsOneWidget);

    await tester.tap(childCheckbox);
    await tester.pump(const Duration(milliseconds: 125));
    await tester.pumpAndSettle();
    var tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');

    await tester.tap(childCheckbox);
    await tester.pump(const Duration(milliseconds: 75));
    await tester.pumpAndSettle();
    tasks = await fake.getTasks(listId: listId);
    expect(tasks.singleWhere((task) => task.id == child.id).status, 'todo');

    await tester.tap(childCheckbox);
    await tester.pump(const Duration(milliseconds: 125));
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    final child = await fake.createTask(
      listId: listId,
      title: 'Open child under closed root',
      parentTaskId: parent.id,
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.setTaskStatus(taskId: parent.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    final childCheckbox = find.byKey(ValueKey('task-done-${child.id}'));
    expect(find.text('Open child under closed root'), findsOneWidget);
    expect(childCheckbox, findsOneWidget);

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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.setTaskStatus(taskId: task.id, status: 'wont_do');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Skipped task'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Skipped task'), findsOneWidget);
    expect(find.byTooltip('Reopen task'), findsOneWidget);

    await _scrollUntilVisible(
      tester,
      find.byKey(ValueKey('task-done-${task.id}')),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.setTaskStatus(taskId: task.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Done task'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
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
    expect(title.style?.decoration, TextDecoration.none);
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
    expect(find.byKey(ValueKey('task-slidable-${first.id}')), findsOneWidget);
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
      due: testDateTimeDueFromMillis(300),
    );
    await fake.updateTask(
      taskId: manualSecond.id,
      title: manualSecond.title,
      note: '',
      priority: 3,
      due: null,
    );
    await fake.updateTask(
      taskId: manualThird.id,
      title: manualThird.title,
      note: '',
      priority: 2,
      due: testDateTimeDueFromMillis(100),
    );
    await fake.updateTask(
      taskId: manualFourth.id,
      title: manualFourth.title,
      note: '',
      priority: 3,
      due: testDateTimeDueFromMillis(400),
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
    expect(doneTitle.style?.decoration, TextDecoration.none);
    expect(wontDoTitle.style?.decoration, TextDecoration.none);
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
    final branchVertical = tester.getRect(
      find.byKey(ValueKey('task-hierarchy-guide-${branchChild.id}')),
    );
    final grandchildVertical = tester.getRect(
      find.byKey(ValueKey('task-hierarchy-guide-${grandchild.id}')),
    );
    final parentCheckbox = tester.getRect(
      find.byKey(ValueKey('task-done-${parent.id}')),
    );
    final branchCheckbox = tester.getRect(
      find.byKey(ValueKey('task-done-${branchChild.id}')),
    );
    final grandchildCheckbox = tester.getRect(
      find.byKey(ValueKey('task-done-${grandchild.id}')),
    );
    final lastCheckbox = tester.getRect(
      find.byKey(ValueKey('task-done-${lastChild.id}')),
    );
    final parentCheckboxVisualCenterX =
        parentCheckbox.left + _taskCheckboxVisualCenterOffset;
    final branchCheckboxVisualCenter = Offset(
      branchCheckbox.left + _taskCheckboxVisualCenterOffset,
      branchCheckbox.center.dy,
    );
    final grandchildCheckboxVisualCenterX =
        grandchildCheckbox.left + _taskCheckboxVisualCenterOffset;
    final lastCheckboxVisualCenterX =
        lastCheckbox.left + _taskCheckboxVisualCenterOffset;
    expect(
      branchVertical.center.dx,
      closeTo(parentCheckboxVisualCenterX, 0.75),
    );
    expect(
      branchHorizontal.right,
      closeTo(
        branchCheckboxVisualCenter.dx -
            _taskCheckboxVisualRadius -
            _taskHierarchyHorizontalEndGap,
        0.75,
      ),
    );
    expect(
      branchHorizontal.center.dy,
      closeTo(branchCheckboxVisualCenter.dy, 0.75),
    );
    expect(
      grandchildVertical.center.dx,
      closeTo(branchCheckboxVisualCenter.dx, 0.75),
    );
    expect(
      branchCheckboxVisualCenter.dx,
      closeTo(lastCheckboxVisualCenterX, 0.75),
    );
    expect(
      grandchildCheckboxVisualCenterX - branchCheckboxVisualCenter.dx,
      closeTo(24, 0.75),
    );
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
    expect(find.text('1 closed'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('completed-section-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

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
      due: testDateTimeDueFromMillis(300),
    );
    await fake.updateTask(
      taskId: childSooner.id,
      title: childSooner.title,
      note: '',
      priority: 0,
      due: testDateTimeDueFromMillis(100),
    );
    await fake.updateTask(
      taskId: otherRoot.id,
      title: otherRoot.title,
      note: '',
      priority: 0,
      due: testDateTimeDueFromMillis(50),
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

    await _ensureFinderVisible(tester, find.text('Add subtask'));
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
        due: testDateOnlyDueFromMillis(_todayStartMs()),
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
      expect(find.text('Task detail'), findsNothing);
      expect(find.text('Parent detail task'), findsOneWidget);
      expect(find.text('Detail child task'), findsOneWidget);
      expect(childCheckbox, findsOneWidget);

      await tester.ensureVisible(childCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(childCheckbox);
      await tester.pump(const Duration(milliseconds: 125));
      await tester.pumpAndSettle();

      var tasks = await fake.getTasks(listId: listId);
      expect(tasks.singleWhere((task) => task.id == child.id).status, 'done');
      expect(find.text('Parent detail task'), findsOneWidget);
      expect(find.text('Task closed.'), findsOneWidget);

      await tester.ensureVisible(childCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(childCheckbox);
      await tester.pump(const Duration(milliseconds: 75));
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
    expect(title.style?.decoration, TextDecoration.none);
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.setTaskStatus(taskId: done.id, status: 'done');
    final wontDo = await fake.createTask(
      listId: listId,
      title: 'Wont do detail task',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.setTaskStatus(taskId: wontDo.id, status: 'wont_do');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(tester, find.text('Done detail task'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
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
    final wontDoRow = find.byKey(ValueKey('task-row-${wontDo.id}'));
    await tester.scrollUntilVisible(
      wontDoRow,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(wontDoRow);
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
        due: testDateOnlyDueFromMillis(_todayStartMs()),
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    final parent = await fake.createTask(
      listId: listId,
      title:
          'Immediate parent task with a title long enough to be ellipsized in the link row',
      parentTaskId: grandparent.id,
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.createTask(
      listId: listId,
      title: 'Child detail task',
      parentTaskId: parent.id,
      due: testDateOnlyDueFromMillis(_todayStartMs()),
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: 'Short note',
      priority: 0,
      due: task.due,
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
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

    await _ensureFinderVisible(tester, find.text('Detail branch child'));
    expect(find.text('Detail branch child'), findsOneWidget);
    await _ensureFinderVisible(tester, find.text('Detail grandchild'));
    expect(find.text('Detail grandchild'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Detail last child'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
        due: testDateOnlyDueFromMillis(_todayStartMs()),
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
        due: testDateOnlyDueFromMillis(_todayStartMs()),
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

    expect(find.byIcon(LucideIcons.squarePen300), findsNothing);
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
    await _ensureFinderVisible(tester, find.text('Subtasks'));
    await tester.tap(find.text('Subtasks'));
    await tester.pumpAndSettle();

    final listId = (await fake.getLists()).first.id;
    final task = (await fake.getTasks(listId: listId)).single;
    final priorityRow = find.byKey(ValueKey('task-priority-chip-${task.id}'));
    await _ensureFinderVisible(tester, priorityRow);
    await tester.tap(priorityRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();

    expect(find.text('Buy oat milk'), findsOneWidget);
    expect(find.text('Shelf-stable'), findsOneWidget);
    await _ensureFinderVisible(tester, priorityRow);
    expect(
      find.byKey(ValueKey('task-priority-dot-${task.id}')),
      findsOneWidget,
    );

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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.updateTask(
      taskId: task.id,
      title: task.title,
      note: 'Stable inline note',
      priority: 0,
      due: testDateOnlyDueFromMillis(_todayStartMs()),
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

    await tester.tap(find.text('Set date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    var active = await fake.getTasks(listId: listId);
    expect(taskDueCivilDate(active.single.due), isNotNull);
    expect(find.text('Task saved.'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('task-clear-due-${task.id}')));
    await tester.pumpAndSettle();

    active = await fake.getTasks(listId: listId);
    expect(active.single.due, isNull);
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
      due: testDateOnlyDueFromMillis(_todayStartMs()),
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
        due: testDateOnlyDueFromMillis(_todayStartMs()),
      );
      final next = await fake.createTask(
        listId: listId,
        title: 'Next task',
        due: testDateOnlyDueFromMillis(_todayStartMs()),
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
