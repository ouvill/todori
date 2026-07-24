import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/main.dart';
import 'package:taskveil/src/core/providers.dart';
import 'package:taskveil/src/rust/api.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets(
    'Templates stays usable at 390px and text scale 2 with schedule semantics',
    (tester) async {
      _useMobileView(tester, textScale: 2);
      final seed = await _seedTemplate(_StreakFakeBridgeService());
      final semantics = tester.ensureSemantics();

      await _pumpTemplates(tester, seed.fake);

      expect(find.text('Templates'), findsNWidgets(2));
      expect(find.text('Morning reset'), findsOneWidget);
      expect(find.text('1 task'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Recurring tasks'), 250);
      await tester.pumpAndSettle();
      expect(find.textContaining('3 streak'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) {
          return widget is Semantics &&
              widget.properties.label == 'Lists' &&
              widget.properties.selected == true;
        }),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((widget) {
          return widget is Semantics &&
              (widget.properties.label ?? '').startsWith(
                'Schedule FREQ=DAILY, next ',
              );
        }),
        findsOneWidget,
      );

      final create = find.text('Create tasks');
      await tester.scrollUntilVisible(create, -250);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text('Tasks created from template.'), findsOneWidget);
      expect(await seed.fake.getTasks(listId: seed.listId), hasLength(2));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'schedule presets validate advanced RRULE and pause/delete with confirmation',
    (tester) async {
      _useMobileView(tester);
      final seed = await _seedTemplate(FakeBridgeService());
      await _pumpTemplates(tester, seed.fake);

      await tester.tap(
        find.byTooltip('Create recurring tasks from this template'),
      );
      await tester.pumpAndSettle();
      expect(find.text('New schedule'), findsOneWidget);
      expect(find.text('Every day'), findsOneWidget);

      await tester.tap(find.text('Every day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced RRULE').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'RRULE'),
        'FREQ=HOURLY',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Check the recurrence rule, start, and time zone.'),
        findsOneWidget,
      );
      expect(await seed.fake.getTaskSeries(), isEmpty);

      await tester.tap(
        find.byTooltip('Create recurring tasks from this template'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      var schedules = await seed.fake.getTaskSeries();
      expect(schedules, hasLength(1));

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      schedules = await seed.fake.getTaskSeries();
      expect(schedules.single.enabled, isFalse);

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete schedule?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await seed.fake.getTaskSeries(), hasLength(1));

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(await seed.fake.getTaskSeries(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('weekly and monthly presets expose explicit selectors', (
    tester,
  ) async {
    _useMobileView(tester, textScale: 2);
    final seed = await _seedTemplate(FakeBridgeService());
    await _pumpTemplates(tester, seed.fake);

    await tester.tap(
      find.byTooltip('Create recurring tasks from this template'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every week on this weekday').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-weekdays')), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(7));
    final initiallySelected = tester
        .widgetList<FilterChip>(find.byType(FilterChip))
        .toList()
        .indexWhere((chip) => chip.selected);
    final additionalWeekday = initiallySelected == 0 ? 1 : 0;
    await tester.tap(find.byType(FilterChip).at(additionalWeekday));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    var schedules = await seed.fake.getTaskSeries();
    expect(schedules.single.rrule, startsWith('FREQ=WEEKLY;BYDAY='));
    expect(schedules.single.rrule.split(',').length, 2);

    await tester.tap(
      find.byTooltip('Create recurring tasks from this template'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every month on this date').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-month-day')), findsOneWidget);
    await tester.tap(find.byKey(const Key('schedule-month-day')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('31').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    schedules = await seed.fake.getTaskSeries();
    expect(
      schedules.map((schedule) => schedule.rrule),
      contains('FREQ=MONTHLY;BYMONTHDAY=31'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Japanese task detail saves a subtree as a template', (
    tester,
  ) async {
    _useMobileView(tester, locale: const Locale('ja'));
    final fake = FakeBridgeService();
    final inbox = await fake.createDefaultList(name: '受信箱', sortOrder: 'a0');
    await fake.createTask(listId: inbox.id, title: '朝の準備');

    await tester.pumpWidget(
      TaskveilApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('リスト').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('受信箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('朝の準備'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('タスク操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('テンプレートとして保存'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '毎朝の準備');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('テンプレートを保存しました。'), findsOneWidget);
    final templates = await fake.getTemplates();
    expect(templates.single.name, '毎朝の準備');
    expect(templates.single.nodes.single.title, '朝の準備');
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates and edits a template blueprint directly', (
    tester,
  ) async {
    _useMobileView(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpTemplates(tester, fake);

    await tester.tap(find.byKey(const Key('create-template')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('template-name')), 'Release');
    await tester.enterText(
      find.byKey(const ValueKey('blueprint-title-root')),
      'Prepare release',
    );
    await tester.tap(find.byKey(const Key('add-blueprint-child')));
    await tester.pumpAndSettle();
    final childTitle = find
        .byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'blueprint-title-node-',
              ),
        )
        .last;
    await tester.enterText(childTitle, 'Publish notes');
    await tester.tap(find.byKey(const Key('add-blueprint-child')));
    await tester.pumpAndSettle();
    final secondChildTitle = find
        .byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'blueprint-title-node-',
              ),
        )
        .last;
    await tester.enterText(secondChildTitle, 'Announce release');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Move up').last);
    await tester.tap(find.byTooltip('Move up').last);
    await tester.pumpAndSettle();
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('save-template')),
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.ensureVisible(find.byKey(const Key('save-template')));
    await tester.tap(find.byKey(const Key('save-template')));
    await tester.pumpAndSettle();

    var templates = await fake.getTemplates();
    expect(templates.single.name, 'Release');
    expect(templates.single.nodes.map((node) => node.title), [
      'Prepare release',
      'Announce release',
      'Publish notes',
    ]);

    await tester.tap(find.byTooltip('Template actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete').last);
    await tester.tap(find.byTooltip('Delete').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-template')));
    await tester.tap(find.byKey(const Key('save-template')));
    await tester.pumpAndSettle();

    templates = await fake.getTemplates();
    expect(templates.single.nodes.map((node) => node.title), [
      'Prepare release',
      'Announce release',
    ]);
    expect(tester.takeException(), isNull);
  });
}

typedef _TemplateSeed = ({
  FakeBridgeService fake,
  String listId,
  String templateId,
});

Future<_TemplateSeed> _seedTemplate(FakeBridgeService fake) async {
  final inbox = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final task = await fake.createTask(
    listId: inbox.id,
    title: 'Prepare the day',
  );
  final template = await fake.saveTaskAsTemplate(
    taskId: task.id,
    name: 'Morning reset',
    defaultListId: inbox.id,
  );
  if (fake is _StreakFakeBridgeService) {
    await fake.createTaskSeriesFromTemplate(
      templateId: template.id,
      rrule: 'FREQ=DAILY',
      startsAt: DateTime(2026, 7, 18, 7).millisecondsSinceEpoch,
      timeZone: 'Asia/Tokyo',
    );
  }
  return (fake: fake, listId: inbox.id, templateId: template.id);
}

Future<void> _pumpTemplates(WidgetTester tester, FakeBridgeService fake) async {
  await tester.pumpWidget(
    TaskveilApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lists').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Templates').last);
  await tester.pumpAndSettle();
}

void _useMobileView(
  WidgetTester tester, {
  double textScale = 1,
  Locale locale = const Locale('en'),
}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.localeTestValue = locale;
  tester.platformDispatcher.localesTestValue = [locale];
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearLocaleTestValue();
    tester.platformDispatcher.clearLocalesTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

class _StreakFakeBridgeService extends FakeBridgeService {
  @override
  Future<StreakDto> getTaskSeriesStreak({
    required String seriesId,
    required int atMs,
  }) async => const StreakDto(current: 3, finalized: false);
}
