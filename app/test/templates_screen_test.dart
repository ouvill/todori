import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/rust/api.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets(
    'Templates stays usable at 390px and text scale 2 with schedule semantics',
    (tester) async {
      _useMobileView(tester, textScale: 2);
      final seed = await _seedTemplate(_StreakFakeBridgeService());
      final semantics = tester.ensureSemantics();

      await _pumpTemplates(tester, seed.fake);

      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Morning reset'), findsOneWidget);
      expect(find.text('1 task'), findsOneWidget);
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
      await tester.ensureVisible(create);
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

      await tester.tap(find.byTooltip('Add schedule'));
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
      expect(
        await seed.fake.getTemplateSchedules(templateId: seed.templateId),
        isEmpty,
      );

      await tester.tap(find.byTooltip('Add schedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      var schedules = await seed.fake.getTemplateSchedules(
        templateId: seed.templateId,
      );
      expect(schedules, hasLength(1));

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      schedules = await seed.fake.getTemplateSchedules(
        templateId: seed.templateId,
      );
      expect(schedules.single.enabled, isFalse);

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete schedule?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await seed.fake.getTemplateSchedules(templateId: seed.templateId),
        hasLength(1),
      );

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(
        await seed.fake.getTemplateSchedules(templateId: seed.templateId),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Japanese task detail saves a subtree as a template', (
    tester,
  ) async {
    _useMobileView(tester, locale: const Locale('ja'));
    final fake = FakeBridgeService();
    final inbox = await fake.createDefaultList(name: '受信箱', sortOrder: 'a0');
    await fake.createTask(listId: inbox.id, title: '朝の準備');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
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
    await fake.createSchedule(
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
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
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
  Future<StreakDto> getScheduleStreak({
    required String scheduleId,
    required int atMs,
  }) async => const StreakDto(current: 3, finalized: false);
}
