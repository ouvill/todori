import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskveil/src/screens/calendar_screen.dart';
import 'package:taskveil/src/screens/focus_screen.dart';
import 'package:taskveil/src/screens/home_screen.dart';
import 'package:taskveil/src/screens/lists_screen.dart';
import 'package:taskveil/src/screens/menu_screen.dart';
import 'package:taskveil/src/screens/search_screen.dart';
import 'package:taskveil/src/screens/task_detail_screen.dart';
import 'package:taskveil/src/screens/templates_screen.dart';

import '../tool/design_lab.dart';
import 'support/design_lab_fixture.dart';

void main() {
  test('Design Lab mode defaults to production baseline', () {
    expect(parseDesignLabMode(''), DesignLabMode.baseline);
    expect(parseDesignLabMode('baseline'), DesignLabMode.baseline);
    expect(parseDesignLabMode('candidate'), DesignLabMode.candidate);
    expect(() => parseDesignLabMode('archive'), throwsArgumentError);
  });

  test(
    'shared fixture covers production planning and template semantics',
    () async {
      final fixture = await createDesignLabFixture(
        referenceTime: DateTime(2026, 7, 19, 12),
      );
      final lists = await fixture.fake.getLists();
      final tasks = await fixture.fake.getTasks(listId: fixture.homeListId);
      final templates = await fixture.fake.getTemplates();
      final schedules = await fixture.fake.getTemplateSchedules(
        templateId: fixture.templateId,
      );
      final reminders = await fixture.fake.getTaskReminders(
        taskId: fixture.parentWithSubtasksId,
      );

      expect(lists.map((list) => list.name), containsAll(['Inbox', '仕事']));
      expect(tasks.any((task) => task.scheduledAt != null), isTrue);
      expect(tasks.any((task) => task.estimatedMinutes != null), isTrue);
      expect(tasks.any((task) => task.priority == 3), isTrue);
      expect(tasks.any((task) => task.status == 'done'), isTrue);
      expect(tasks.any((task) => task.status == 'wont_do'), isTrue);
      expect(tasks.any((task) => task.title.contains('地図アプリ')), isTrue);
      expect(
        tasks.where((task) => task.parentTaskId != null).length,
        greaterThanOrEqualTo(4),
      );
      expect(reminders, hasLength(2));
      expect(templates.single.name, 'Weekly launch review');
      expect(schedules.single.rrule, 'FREQ=WEEKLY');
    },
  );

  testWidgets('baseline runs production routes instead of Design Lab mocks', (
    tester,
  ) async {
    _setViewport(tester);
    final baseline = await createDesignLabBaseline();
    addTearDown(baseline.router.dispose);
    await tester.pumpWidget(baseline.root);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Calendar'), findsWidgets);
    expect(find.text('Lists'), findsWidgets);
    expect(find.text('Menu'), findsWidgets);

    baseline.router.go('/calendar');
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    baseline.router.go('/lists');
    await tester.pumpAndSettle();
    expect(find.byType(ListsScreen), findsOneWidget);

    baseline.router.go('/menu');
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);

    baseline.router.go('/templates');
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesScreen), findsOneWidget);
    expect(find.text('Weekly launch review'), findsOneWidget);

    baseline.router.go('/search');
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);

    baseline.router.go(
      '/lists/${baseline.fixture.homeListId}/tasks/'
      '${baseline.fixture.parentWithSubtasksId}',
    );
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailScreen), findsOneWidget);
    expect(find.text(baseline.fixture.parentWithSubtasksTitle), findsOneWidget);

    baseline.router.go(
      '/focus/${baseline.fixture.homeListId}/'
      '${baseline.fixture.focusTaskId}',
    );
    await tester.pumpAndSettle();
    expect(find.byType(FocusScreen), findsOneWidget);
  });

  test('candidate registry rejects incomplete and duplicate contracts', () {
    Widget builder(BuildContext context) => const SizedBox.shrink();
    const workItem = '019f765f-66b2-7b93-a9fd-8ddd16ad3107';
    final valid = DesignLabCandidate(
      id: 'home-density-a',
      targetRoute: '/',
      hypothesis: 'A tighter first viewport improves scanning.',
      uiSpecDelta: 'Section 2 spacing only.',
      workItem: workItem,
      builder: builder,
    );
    expect(validateDesignLabCandidates([valid]), isEmpty);
    expect(
      validateDesignLabCandidates([valid, valid]),
      contains('duplicate candidate id: home-density-a'),
    );
    final invalid = DesignLabCandidate(
      id: '',
      targetRoute: 'home',
      hypothesis: '',
      uiSpecDelta: '',
      workItem: 'task-33',
      builder: builder,
    );
    expect(validateDesignLabCandidates([invalid]), hasLength(5));
  });

  testWidgets('candidate mode has an explicit empty state', (tester) async {
    _setViewport(tester);
    expect(activeDesignLabCandidates, isEmpty);
    final root = await buildDesignLabRoot(mode: DesignLabMode.candidate);
    await tester.pumpWidget(root);
    await tester.pumpAndSettle();
    expect(find.text('No active design candidate'), findsOneWidget);
    expect(find.textContaining('DesignLabCandidate'), findsOneWidget);
  });
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
