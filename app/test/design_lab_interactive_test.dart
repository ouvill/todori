import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'visual_qa/design_lab_mocks.dart';

void main() {
  testWidgets('Design Lab navigation and task capture are interactive', (
    tester,
  ) async {
    _setDesignLabViewport(tester);
    await tester.pumpWidget(const InteractiveDesignLabApp());

    await tester.tap(find.byIcon(LucideIcons.calendarDays300));
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsAtLeastNWidgets(1));
    expect(find.text('TUESDAY 27'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Approved release direction'), findsNothing);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Approved release direction'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.listTodo300));
    await tester.pumpAndSettle();
    expect(find.text('YOUR LISTS'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.plus300));
    await tester.pumpAndSettle();
    expect(find.text('What needs doing?'), findsOneWidget);

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
