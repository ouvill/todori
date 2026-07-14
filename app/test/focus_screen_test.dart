import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/router.dart';
import 'package:todori/src/rust/api.dart' show TimerFinishKindDto;
import 'package:todori/src/screens/focus_screen.dart';
import 'package:todori/src/timer/timer_engine.dart';
import 'package:todori/src/ui/theme.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets(
    'Focus lifecycle preserves status and complete then Undo never restarts timer',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).single.id;
      final task = await fake.createTask(
        listId: listId,
        title: 'Write the quiet launch note',
        estimatedMinutes: 25,
      );
      final clock = _MutableTimerClock(DateTime.utc(2026, 7, 13, 9));
      final router = buildAppRouter();

      await tester.pumpWidget(
        TodoriApp(
          router: router,
          overrides: [
            bridgeServiceProvider.overrideWithValue(fake),
            timerClockProvider.overrideWithValue(clock),
          ],
        ),
      );
      await tester.pumpAndSettle();
      router.go('/focus/$listId/${task.id}');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('focus-setup')), findsOneWidget);
      expect(find.text('Write the quiet launch note'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('focus-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
      expect((await fake.getTasks(listId: listId)).single.status, 'todo');

      clock.advance(const Duration(minutes: 1));
      await tester.tap(find.byKey(const ValueKey('focus-pause')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('focus-paused')), findsOneWidget);
      expect((await fake.getTasks(listId: listId)).single.status, 'todo');

      await tester.tap(find.byKey(const ValueKey('focus-session-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('focus-complete-task')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect((await fake.getTasks(listId: listId)).single.status, 'done');
      expect(await fake.getActiveTimerSession(), isNull);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect((await fake.getTasks(listId: listId)).single.status, 'todo');
      expect(await fake.getActiveTimerSession(), isNull);

      router.go('/lists/$listId/tasks/${task.id}');
      await tester.pumpAndSettle();
      final summary = find.byKey(ValueKey('task-focus-summary-${task.id}'));
      await tester.scrollUntilVisible(summary, 160);
      expect(find.text('1m actual · 25m estimated'), findsOneWidget);

      router.go('/focus/$listId/${task.id}');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('focus-start-break')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('focus-break-running')), findsOneWidget);
      expect(find.text('Save and exit'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('focus-session-options')));
      await tester.pumpAndSettle();
      expect(find.text('End break'), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-add-time')), findsNothing);
      expect(find.byKey(const ValueKey('focus-complete-task')), findsNothing);
      expect(find.byKey(const ValueKey('focus-save-and-exit')), findsNothing);
    },
  );

  testWidgets(
    'Focus clock fits 320px at text scale 2 and exposes stable semantics',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final fake = FakeBridgeService();
      await fake.createDefaultList(name: '受信箱', sortOrder: 'a0');
      final listId = (await fake.getLists()).single.id;
      final task = await fake.createTask(
        listId: listId,
        title: '長いタイトルでも落ち着いて集中できることを確認する',
      );
      final router = GoRouter(
        initialLocation: '/focus/$listId/${task.id}',
        routes: [
          GoRoute(
            path: '/focus/:listId/:taskId',
            builder: (context, state) => FocusScreen(
              listId: state.pathParameters['listId']!,
              taskId: state.pathParameters['taskId']!,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        TodoriApp(
          router: router,
          overrides: [bridgeServiceProvider.overrideWithValue(fake)],
        ),
      );
      await tester.pumpAndSettle();
      final modeSelector = find.byKey(const ValueKey('focus-mode-selector'));
      await tester.scrollUntilVisible(modeSelector, 160);
      expect(modeSelector, findsOneWidget);
      final start = find.byKey(const ValueKey('focus-start'));
      await tester.scrollUntilVisible(start, 180);
      await tester.tap(start);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('focus-clock')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('focus-clock')),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Focusing')), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pomodoro break prompt survives restart and Done clears it', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Keep the break handoff durable',
    );
    final clock = _MutableTimerClock(DateTime.utc(2026, 7, 13, 10));

    Future<GoRouter> pumpFreshApp() async {
      final router = buildAppRouter();
      await tester.pumpWidget(
        TodoriApp(
          router: router,
          overrides: [
            bridgeServiceProvider.overrideWithValue(fake),
            timerClockProvider.overrideWithValue(clock),
          ],
        ),
      );
      await tester.pumpAndSettle();
      router.go('/focus/$listId/${task.id}');
      await tester.pumpAndSettle();
      return router;
    }

    await pumpFreshApp();
    await tester.tap(find.byKey(const ValueKey('focus-start')));
    await tester.pump(const Duration(milliseconds: 100));
    clock.advance(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('focus-session-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-finish')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('focus-start-break')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpFreshApp();
    expect(find.byKey(const ValueKey('focus-start-break')), findsOneWidget);
    expect(find.text('Take a breath.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('focus-done')));
    await tester.pumpAndSettle();
    expect(await fake.getActiveTimerSession(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpFreshApp();
    expect(find.byKey(const ValueKey('focus-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-start-break')), findsNothing);
  });

  testWidgets('Complete task requires a saved non-zero work session', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Do not complete before work is saved',
    );
    final router = buildAppRouter();
    await tester.pumpWidget(
      TodoriApp(
        router: router,
        overrides: [
          bridgeServiceProvider.overrideWithValue(fake),
          timerClockProvider.overrideWithValue(
            _MutableTimerClock(DateTime.utc(2026, 7, 13, 11)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    router.go('/focus/$listId/${task.id}');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-start')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('focus-session-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-complete-task')));
    await tester.pump(const Duration(milliseconds: 200));

    expect((await fake.getTasks(listId: listId)).single.status, 'todo');
    expect(await fake.getActiveTimerSession(), isNull);
    expect(await fake.getCompletedTimerSessions(taskId: task.id), isEmpty);
  });

  testWidgets(
    'Focus keeps the warm canvas and groups secondary work actions in one sheet',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).single.id;
      final task = await fake.createTask(
        listId: listId,
        title: 'Refine the quiet timer',
      );
      final router = buildAppRouter();
      await tester.pumpWidget(
        TodoriApp(
          router: router,
          overrides: [bridgeServiceProvider.overrideWithValue(fake)],
        ),
      );
      await tester.pumpAndSettle();
      router.go('/focus/$listId/${task.id}');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('focus-screen')))
            .backgroundColor,
        AppColors.canvas,
      );
      await tester.tap(find.byKey(const ValueKey('focus-start')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('focus-screen')))
            .backgroundColor,
        AppColors.canvas,
      );
      expect(find.byKey(const ValueKey('focus-add-time')), findsNothing);
      expect(find.byKey(const ValueKey('focus-finish')), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('focus-pause'))).shortestSide,
        greaterThanOrEqualTo(64),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('focus-session-options')))
            .height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.byKey(const ValueKey('focus-session-options')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-add-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-finish')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-complete-task')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-save-and-exit')), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-discard')), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('focus-pause')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('focus-paused')), findsOneWidget);
      expect(
        tester
            .widget<Scaffold>(find.byKey(const ValueKey('focus-screen')))
            .backgroundColor,
        AppColors.canvas,
      );
    },
  );

  testWidgets(
    'close and system back open the same session sheet and discard confirms',
    (tester) async {
      final fake = FakeBridgeService();
      await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
      final listId = (await fake.getLists()).single.id;
      final task = await fake.createTask(
        listId: listId,
        title: 'Keep exit behavior predictable',
      );
      final router = buildAppRouter();
      await tester.pumpWidget(
        TodoriApp(
          router: router,
          overrides: [bridgeServiceProvider.overrideWithValue(fake)],
        ),
      );
      await tester.pumpAndSettle();
      router.go('/focus/$listId/${task.id}');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('focus-start')));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.byKey(const ValueKey('focus-close')).hitTestable().last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-discard')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await fake.getActiveTimerSession(), isNotNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-discard')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('focus-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this session?'), findsOneWidget);
      expect(await fake.getActiveTimerSession(), isNotNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await fake.getActiveTimerSession(), isNotNull);

      await tester.tap(find.byKey(const ValueKey('focus-session-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('focus-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(await fake.getActiveTimerSession(), isNull);
    },
  );

  testWidgets('Save and exit records work and allows a new focus session', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Return for another focus session',
    );
    final clock = _MutableTimerClock(DateTime.utc(2026, 7, 14, 9));
    final router = buildAppRouter();
    await tester.pumpWidget(
      TodoriApp(
        router: router,
        overrides: [
          bridgeServiceProvider.overrideWithValue(fake),
          timerClockProvider.overrideWithValue(clock),
        ],
      ),
    );
    await tester.pumpAndSettle();
    router.go('/focus/$listId/${task.id}');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-start')));
    await tester.pump(const Duration(milliseconds: 300));

    clock.advance(const Duration(minutes: 3));
    await tester.tap(find.byKey(const ValueKey('focus-session-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-save-and-exit')));
    await tester.pumpAndSettle();

    expect(await fake.getActiveTimerSession(), isNull);
    final sessions = await fake.getCompletedTimerSessions(taskId: task.id);
    expect(sessions, hasLength(1));
    expect(sessions.single.finishKind, TimerFinishKindDto.interrupted);

    router.go('/focus/$listId/${task.id}');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-finished')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('focus-start')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
    expect(await fake.getActiveTimerSession(), isNotNull);
  });

  testWidgets('Focus setup and active controls remain usable in RTL', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Read from either direction',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: FocusScreen(listId: listId, taskId: task.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('focus-mode-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-preview-clock')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('focus-start')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-pause')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-session-options')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stopwatch uses a static dial and never offers add time', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Measure an open-ended session',
    );
    final router = buildAppRouter();
    await tester.pumpWidget(
      TodoriApp(
        router: router,
        overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      ),
    );
    await tester.pumpAndSettle();
    router.go('/focus/$listId/${task.id}');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stopwatch'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('focus-start')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('focus-session-options')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('focus-add-time')), findsNothing);
    expect(find.byKey(const ValueKey('focus-finish')), findsOneWidget);
    expect(find.text('Finish session'), findsOneWidget);
  });

  testWidgets('Reduce Motion switches into Focus without a transition delay', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).single.id;
    final task = await fake.createTask(
      listId: listId,
      title: 'Enter focus without decorative motion',
    );
    final router = buildAppRouter();
    await tester.pumpWidget(
      TodoriApp(
        router: router,
        overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      ),
    );
    await tester.pumpAndSettle();
    router.go('/focus/$listId/${task.id}');
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('focus-start'));
    await tester.scrollUntilVisible(start, 120);
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
    expect(
      tester
          .widget<Scaffold>(find.byKey(const ValueKey('focus-screen')))
          .backgroundColor,
      AppColors.canvas,
    );
  });

  testWidgets('missing Focus task exposes a visible exit to Home', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final list = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final router = buildAppRouter();
    await tester.pumpWidget(
      TodoriApp(
        router: router,
        overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      ),
    );
    await tester.pumpAndSettle();
    router.go('/focus/${list.id}/missing-task');
    await tester.pumpAndSettle();

    expect(
      find.text("Todori couldn't restore this focus session."),
      findsOneWidget,
    );
    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
  });
}

class _MutableTimerClock implements TimerClock {
  _MutableTimerClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
  void advance(Duration duration) => value = value.add(duration);
}
