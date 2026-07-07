import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/screens/tasks_screen.dart';

import 'support/fake_bridge_service.dart';

void main() {
  testWidgets('task-67 pumps Home with 10000 fake tasks', (tester) async {
    final fake = FakeBridgeService();
    final seed = fake.seedLargeDataset();

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    stopwatch.stop();

    debugPrint(
      'task-67 Flutter pump: screen=Home '
      'lists=${seed.listCount} tasks=${seed.taskCount} '
      'due=${seed.dueTaskCount} closed=${seed.closedTaskCount} '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    expect(find.textContaining('Task '), findsWidgets);
  });

  testWidgets('task-67 pumps a 1000-task list from the 10000 fake seed', (
    tester,
  ) async {
    final fake = FakeBridgeService();
    final seed = fake.seedLargeDataset();
    final router = GoRouter(
      initialLocation: '/lists/${seed.defaultListId}/tasks',
      routes: [
        GoRoute(
          path: '/lists/:listId/tasks',
          builder: (context, state) =>
              TasksScreen(listId: state.pathParameters['listId']!),
        ),
      ],
    );

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      TodoriApp(
        router: router,
        overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      ),
    );
    await tester.pumpAndSettle();
    stopwatch.stop();

    debugPrint(
      'task-67 Flutter pump: screen=Tasks '
      'visible_list_tasks=1000 total_tasks=${seed.taskCount} '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    expect(find.textContaining('Task '), findsWidgets);
  });
}
