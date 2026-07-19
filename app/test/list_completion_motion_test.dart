import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/main.dart';
import 'package:taskveil/src/core/providers.dart';
import 'package:taskveil/src/router.dart';
import 'package:taskveil/src/rust/api.dart';
import 'package:taskveil/src/ui/task_completion_motion.dart';
import 'package:taskveil/src/ui/task_components.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets(
    'list root completion keeps checkbox identity through hold and collapse',
    (tester) async {
      final seeded = await _pumpList(tester, FakeBridgeService());
      final checkbox = find.byKey(ValueKey('task-done-${seeded.task.id}'));
      final stateBefore = tester.state(
        find.ancestor(of: checkbox, matching: find.byType(AppTaskCheckbox)),
      );

      await tester.tap(checkbox);
      await tester.pump();
      final stateAfter = tester.state(
        find.ancestor(of: checkbox, matching: find.byType(AppTaskCheckbox)),
      );
      expect(identical(stateBefore, stateAfter), isTrue);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('List motion root'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-completion-halo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('task-strikethrough-overlay')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 449));
      expect(find.text('List motion root'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2));
      final exit = tester.widget<AppTaskCompletionExit>(
        find.byKey(ValueKey('task-list-completion-exit-${seeded.task.id}')),
      );
      expect(exit.isExiting, isTrue);
      expect(find.text('List motion root'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 420));
      expect(find.text('List motion root'), findsNothing);
      expect(
        find.byKey(const ValueKey('completed-section-toggle')),
        findsOneWidget,
      );
    },
  );

  testWidgets('nested completion animates in place without leaving hierarchy', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final seeded = await _pumpList(tester, fake, includeChild: true);
    final child = seeded.child!;
    final checkbox = find.byKey(ValueKey('task-done-${child.id}'));
    final stateBefore = tester.state(
      find.ancestor(of: checkbox, matching: find.byType(AppTaskCheckbox)),
    );
    final topBefore = tester.getTopLeft(
      find.byKey(ValueKey('task-row-${child.id}')),
    );

    await tester.tap(checkbox);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final stateAfter = tester.state(
      find.ancestor(of: checkbox, matching: find.byType(AppTaskCheckbox)),
    );
    expect(identical(stateBefore, stateAfter), isTrue);
    expect(find.byKey(const ValueKey('task-completion-halo')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('task-row-${child.id}'))),
      topBefore,
    );

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Nested motion child'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('task-row-${child.id}'))),
      topBefore,
    );
    expect((await fake.getTasks(listId: seeded.listId)).last.status, 'done');
  });

  testWidgets('list completion is immediate with Reduce Motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final seeded = await _pumpList(tester, FakeBridgeService());

    await tester.tap(find.byKey(ValueKey('task-done-${seeded.task.id}')));
    await tester.pumpAndSettle();

    expect(find.text('List motion root'), findsNothing);
    expect(find.byKey(const ValueKey('task-completion-halo')), findsNothing);
    expect(
      find.byKey(const ValueKey('completed-section-toggle')),
      findsOneWidget,
    );
  });

  testWidgets('failed list completion rolls optimistic row back', (
    tester,
  ) async {
    final fake = _FailingStatusBridge();
    final seeded = await _pumpList(tester, fake);

    await tester.tap(find.byKey(ValueKey('task-done-${seeded.task.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('List motion root'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-completion-halo')), findsNothing);
    expect((await fake.getTasks(listId: seeded.listId)).single.status, 'todo');
  });
}

Future<({String listId, TaskDto task, TaskDto? child})> _pumpList(
  WidgetTester tester,
  FakeBridgeService fake, {
  bool includeChild = false,
}) async {
  final list = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final task = await fake.createTask(
    listId: list.id,
    title: 'List motion root',
  );
  final child = includeChild
      ? await fake.createTask(
          listId: list.id,
          title: 'Nested motion child',
          parentTaskId: task.id,
        )
      : null;
  final router = buildAppRouter();
  await tester.pumpWidget(
    TaskveilApp(
      router: router,
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
    ),
  );
  await tester.pumpAndSettle();
  router.go('/lists/${list.id}/tasks');
  await tester.pumpAndSettle();
  return (listId: list.id, task: task, child: child);
}

class _FailingStatusBridge extends FakeBridgeService {
  @override
  Future<TaskDto> setTaskStatus({
    required String taskId,
    required String status,
    String? closedReason,
  }) {
    throw StateError('simulated completion failure');
  }
}
