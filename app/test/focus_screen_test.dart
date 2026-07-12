import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/router.dart';
import 'package:todori/src/screens/focus_screen.dart';
import 'package:todori/src/timer/timer_engine.dart';

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
      expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
      expect(find.text('Save and exit'), findsNothing);
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
      final stackedSelector = find.byKey(
        const ValueKey('focus-mode-selector-stacked'),
      );
      await tester.scrollUntilVisible(stackedSelector, 160);
      expect(stackedSelector, findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('focus-complete-task')));
    await tester.pump(const Duration(milliseconds: 200));

    expect((await fake.getTasks(listId: listId)).single.status, 'todo');
    expect(await fake.getActiveTimerSession(), isNull);
    expect(await fake.getCompletedTimerSessions(taskId: task.id), isEmpty);
  });
}

class _MutableTimerClock implements TimerClock {
  _MutableTimerClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
  void advance(Duration duration) => value = value.add(duration);
}
