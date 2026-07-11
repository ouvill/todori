import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'visual_qa/design_lab_mocks.dart';

void main() {
  testWidgets('Design Lab navigation and task capture are interactive', (
    tester,
  ) async {
    _setDesignLabViewport(tester);
    await tester.pumpWidget(const InteractiveDesignLabApp());
    _expectIconCentered(tester, LucideIcons.search300);
    expect(find.text('Verify reduced motion'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('See the rest of the week'), findsNothing);
    expect(
      find.byKey(const ValueKey('design-lab-completion-particles')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('design-lab-task-check-Review onboarding copy'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const ValueKey('design-lab-completion-particles')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('design-lab-strikethrough')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(LucideIcons.calendarDays300));
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsAtLeastNWidgets(1));
    expect(find.text('TUESDAY 27'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('4 this week'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('design-lab-strikethrough')),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Approved release direction'), findsNothing);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Approved release direction'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.listTodo300));
    await tester.pumpAndSettle();
    expect(find.text('YOUR LISTS'), findsOneWidget);

    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();
    expect(find.text('MANUAL ORDER'), findsOneWidget);
    expect(find.text('Verify reduced motion'), findsOneWidget);
    _expectIconCentered(tester, LucideIcons.arrowLeft300);
    _expectIconCentered(tester, LucideIcons.moreHorizontal300);

    await tester.drag(find.text('Prepare launch notes'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('design-lab-task-focus-Prepare launch notes')),
    );
    await tester.pumpAndSettle();
    expect(find.text('SET FOCUS'), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.x300));
    await tester.pumpAndSettle();
    expect(find.text('MANUAL ORDER'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('design-lab-list-actions')));
    await tester.pumpAndSettle();
    expect(find.text('LIST ACTIONS'), findsOneWidget);
    await tester.tap(find.text('Change a task due date'));
    await tester.pumpAndSettle();
    expect(find.text('DUE DATE'), findsOneWidget);
    expect(find.text('This weekend'), findsOneWidget);
    await tester.tapAt(const Offset(12, 100));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.arrowLeft300));
    await tester.pumpAndSettle();
    expect(find.text('YOUR LISTS'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.circleUserRound300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Youhei'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.tap(find.text('CREATE ACCOUNT'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.arrowLeft300));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus300));
    await tester.pumpAndSettle();
    expect(find.text('What needs doing?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('design-lab-composer-list')));
    await tester.tap(find.byKey(const ValueKey('design-lab-composer-due')));
    await tester.tap(find.byKey(const ValueKey('design-lab-composer-plan')));
    await tester.tap(
      find.byKey(const ValueKey('design-lab-composer-priority')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('design-lab-composer-list')),
        matching: find.text('Design'),
      ),
      findsOneWidget,
    );
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.arrowUp300));
    await tester.pumpAndSettle();
    expect(find.text('What needs doing?'), findsNothing);
  });

  testWidgets('Design Lab connects task detail, focus setup, and live timer', (
    tester,
  ) async {
    _setDesignLabViewport(tester);
    await tester.pumpWidget(const InteractiveDesignLabApp());

    await tester.tap(find.text('Prepare launch notes'));
    await tester.pumpAndSettle();
    expect(find.text('Begin a 25 minute focus'), findsOneWidget);
    expect(find.text('Confirm product highlights'), findsOneWidget);

    await tester.tap(find.text('Prepare launch notes'));
    await tester.pumpAndSettle();
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('Reminder'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('design-lab-save-task')));
    await tester.pumpAndSettle();
    expect(find.text('Begin a 25 minute focus'), findsOneWidget);

    await tester.tap(find.text('Begin a 25 minute focus'));
    await tester.pumpAndSettle();
    expect(find.text('SET FOCUS'), findsOneWidget);

    await tester.tap(find.text('45'));
    await tester.pump();
    expect(find.text('45'), findsNWidgets(2));

    await tester.tap(find.byIcon(LucideIcons.plus300));
    await tester.pump();
    expect(find.text('50'), findsOneWidget);

    await tester.tap(find.text('Begin focus  →'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('FOCUS  ·  1 OF 4'), findsOneWidget);
    expect(find.text('50:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('49:59'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Begin a 25 minute focus'), findsOneWidget);
  });
}

void _setDesignLabViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _expectIconCentered(WidgetTester tester, IconData icon) {
  final iconFinder = find.byIcon(icon).first;
  final buttonFinder = find
      .ancestor(of: iconFinder, matching: find.byType(IconButton))
      .first;
  final iconCenter = tester.getCenter(iconFinder);
  final buttonCenter = tester.getCenter(buttonFinder);
  expect((iconCenter - buttonCenter).distance, lessThan(0.01));
}
