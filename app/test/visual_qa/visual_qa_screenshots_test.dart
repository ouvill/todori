// Visual QA screenshot harness.
//
// This is not part of the automated quality gate. It builds a handful of
// curated, screenshot-worthy app states -- with a real system font and the
// bundled Material Icons font loaded so nothing renders as "tofu" -- and
// rasterizes each one to a PNG under `build/visual_qa/` for design review.
//
// Every test in this file is skipped unless the `TODORI_VISUAL_QA=1`
// environment variable is set, so a plain `flutter test` (and CI) never
// pays the cost of loading real fonts or writing screenshots to disk.
//
// Usage: `sh tool/visual_qa.sh` from `app/`, or directly:
//   TODORI_VISUAL_QA=1 flutter test test/visual_qa/visual_qa_screenshots_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';
import 'package:todori/src/router.dart';
import 'package:todori/src/rust/api.dart'
    show
        ActiveTimerSessionDto,
        CalendarOccurrenceDto,
        CalendarRangeInput,
        TaskDto,
        TimerModeDto,
        TimerPhaseDto,
        TimerRunStateDto;
import 'package:todori/src/screens/calendar_screen.dart';
import 'package:todori/src/screens/search_screen.dart';
import 'package:todori/src/timer/timer_engine.dart' show TimerClock;
import 'package:todori/src/ui/task_components.dart';
import 'package:todori/src/ui/theme.dart';

import 'design_lab_mocks.dart';
import '../support/fake_bridge_service.dart';

const _visualQaEnvFlag = 'TODORI_VISUAL_QA';

bool get _visualQaEnabled => Platform.environment[_visualQaEnvFlag] == '1';

const _outputDir = 'build/visual_qa';
const _mobileLogicalSize = Size(390, 844);
const _mobileDevicePixelRatio = 3.0;
const _wideLogicalSize = Size(1100, 760);
const _wideDevicePixelRatio = 2.0;

/// Downloaded (not committed) by `tool/fetch_lab_fonts.sh`; used only by the
/// `design_lab_typo_d_ja_mincho_*` screenshots (D案). See
/// `docs/design/ui-spec.md` セクション6.
const _zenOldMinchoFontPath = 'build/lab_fonts/ZenOldMincho-SemiBold.ttf';

bool get _zenOldMinchoFontAvailable => File(_zenOldMinchoFontPath).existsSync();

void main() {
  if (!_visualQaEnabled) {
    test(
      'visual QA screenshots are skipped unless $_visualQaEnvFlag=1 is set',
      () {},
      skip:
          'This is a design-review screenshot harness, not a regression '
          'test. Run `sh tool/visual_qa.sh` to generate build/visual_qa/*.png.',
    );
    return;
  }

  setUpAll(_loadRealFonts);

  testWidgets('onboarding_en: first-run welcome', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService(onboardingCompleted: false);
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Make room for what matters'), findsOneWidget);
    await _screenshot(tester, 'onboarding_en');
  });

  testWidgets('onboarding_ja: first-run welcome', (tester) async {
    _setMobileViewport(tester);
    _useJaLocale(tester);
    final fake = FakeBridgeService(onboardingCompleted: false);
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('大切なことに、余白を'), findsOneWidget);
    await _screenshot(tester, 'onboarding_ja');
  });

  testWidgets('onboarding_text_scale_2: first run at Dynamic Type 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    final fake = FakeBridgeService(onboardingCompleted: false);
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Make room for what matters'), findsOneWidget);
    await _screenshot(tester, 'onboarding_text_scale_2');
  });

  testWidgets('focus_setup: warm immersive setup', (tester) async {
    _setMobileViewport(tester);
    await _pumpFocusVisual(tester);
    await _screenshot(tester, 'focus_setup');
  });

  testWidgets('focus_running: dark inverse work session', (tester) async {
    _setMobileViewport(tester);
    await _pumpFocusVisual(tester, state: _FocusVisualState.running);
    await _screenshot(tester, 'focus_running');
  });

  testWidgets('focus_paused: dark inverse paused controls', (tester) async {
    _setMobileViewport(tester);
    await _pumpFocusVisual(tester, state: _FocusVisualState.paused);
    await _screenshot(tester, 'focus_paused');
  });

  testWidgets('focus_finished: recorded work handoff', (tester) async {
    _setMobileViewport(tester);
    await _pumpFocusVisual(tester, state: _FocusVisualState.finished);
    await _screenshot(tester, 'focus_finished');
  });

  testWidgets('focus_restored_running: durable background restore', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpRestoredFocusVisual(tester);
    await _screenshot(tester, 'focus_restored_running');
  });

  testWidgets('focus_error: timer restore failure', (tester) async {
    _setMobileViewport(tester);
    await _pumpFocusErrorVisual(tester);
    await _screenshot(tester, 'focus_error');
  });

  testWidgets('focus_320_ja_text_scale_2: narrow accessible setup', (
    tester,
  ) async {
    _setLogicalViewport(tester, const Size(320, 844), devicePixelRatio: 2);
    _useJaLocale(tester);
    _useTextScale(tester, 2);
    await _pumpFocusVisual(tester, taskTitle: '静かな集中画面を日本語で確認する');
    await _screenshot(tester, 'focus_320_ja_text_scale_2');
  });

  testWidgets('focus_720_setup: compact wide setup', (tester) async {
    _setLogicalViewport(tester, const Size(720, 760), devicePixelRatio: 2);
    await _pumpFocusVisual(tester);
    await _screenshot(tester, 'focus_720_setup');
  });

  testWidgets('focus_1024_running: centered wide timer', (tester) async {
    _setLogicalViewport(tester, const Size(1024, 760), devicePixelRatio: 2);
    await _pumpFocusVisual(tester, state: _FocusVisualState.running);
    await _screenshot(tester, 'focus_1024_running');
  });

  testWidgets('home_tasks: root with a realistic mixed task list', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    expect(
      find.text(formatHomeHeaderDate('en', DateTime.now())),
      findsOneWidget,
    );
    await _screenshot(tester, 'home_tasks');
  });

  testWidgets('home_tasks_wide: responsive navigation rail', (tester) async {
    _setWideViewport(tester);
    await _seedRealisticData(tester);
    await _screenshot(tester, 'home_tasks_wide');
  });

  testWidgets('home_tasks_completed: completed outcome disclosure', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('completed-section-toggle')),
    );
    await _screenshot(tester, 'home_tasks_completed');
  });

  testWidgets('lists_wide: list management with navigation rail', (
    tester,
  ) async {
    _setWideViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists_wide');
  });

  testWidgets(
    'home_tasks_ja: root with a realistic mixed task list, ja locale',
    (tester) async {
      _setMobileViewport(tester);
      _useJaLocale(tester);
      await _seedRealisticData(tester);
      expect(
        find.text(formatHomeHeaderDate('ja', DateTime.now())),
        findsOneWidget,
      );
      await _screenshot(tester, 'home_tasks_ja');
    },
  );

  testWidgets('home_tasks_dark: dark priority dot contrast check', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useDarkPlatformBrightness(tester);
    await _seedRealisticData(tester);
    await _screenshot(tester, 'home_tasks_dark');
  });

  testWidgets('home_tasks_empty: root list with zero tasks', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, 'home_tasks_empty');
  });

  testWidgets('home_tasks_text_scale_2: Home at Dynamic Type 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    await _seedRealisticData(tester);
    await _screenshot(tester, 'home_tasks_text_scale_2');
  });

  testWidgets('calendar_week_390: production Week route', (tester) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData());
    await _screenshot(tester, 'calendar_week_390');
  });

  testWidgets('calendar_week_completed_closed: quiet disclosure', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarCompletedVisualData());
    expect(
      find.byKey(const ValueKey('calendar-completed-toggle')),
      findsOneWidget,
    );
    await _screenshot(tester, 'calendar_week_completed_closed');
  });

  testWidgets('calendar_week_completed_open: completed outcomes expanded', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarCompletedVisualData());
    await tester.tap(find.byKey(const ValueKey('calendar-completed-toggle')));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'calendar_week_completed_open');
  });

  testWidgets('calendar_week_ja: Japanese production Week', (tester) async {
    _setMobileViewport(tester);
    _useJaLocale(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData());
    await _screenshot(tester, 'calendar_week_ja');
  });

  testWidgets('calendar_week_text_scale_2: Week at Dynamic Type 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    await _pumpCalendarVisual(tester, await _calendarVisualData());
    await _screenshot(tester, 'calendar_week_text_scale_2');
  });

  testWidgets('calendar_week_narrow_320: Week at 320px', (tester) async {
    _setNarrowViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData());
    await _screenshot(tester, 'calendar_week_narrow_320');
  });

  testWidgets('calendar_week_rtl: production Calendar under RTL', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final fake = await _calendarVisualData();
    await _pumpCalendarVisualRtl(tester, fake);
    await _screenshot(tester, 'calendar_week_rtl');
  });

  testWidgets('calendar_month_390: production Month route', (tester) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData(), month: true);
    await _screenshot(tester, 'calendar_month_390');
  });

  testWidgets('calendar_month_selected_day: selected-day agenda', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData(), month: true);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(
      find.byKey(ValueKey('calendar-month-day-${_visualCivilDate(tomorrow)}')),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, 'calendar_month_selected_day');
  });

  testWidgets('calendar_month_narrow_320: Month at 320px', (tester) async {
    _setNarrowViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData(), month: true);
    await _screenshot(tester, 'calendar_month_narrow_320');
  });

  testWidgets('calendar_wide_720_single: wide single-column threshold', (
    tester,
  ) async {
    _setLogicalViewport(tester, const Size(720, 760), devicePixelRatio: 2);
    await _pumpCalendarVisual(tester, await _calendarVisualData(), month: true);
    await _screenshot(tester, 'calendar_wide_720_single');
  });

  testWidgets('calendar_wide_1024_two_pane: Month grid and agenda', (
    tester,
  ) async {
    _setLogicalViewport(tester, const Size(1024, 760), devicePixelRatio: 2);
    await _pumpCalendarVisual(tester, await _calendarVisualData(), month: true);
    await _screenshot(tester, 'calendar_wide_1024_two_pane');
  });

  testWidgets('calendar_empty: empty selected day', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpCalendarVisual(tester, fake);
    await _screenshot(tester, 'calendar_empty');
  });

  testWidgets('calendar_loading: pending range query', (tester) async {
    _setMobileViewport(tester);
    final fake = _PendingVisualCalendarBridge();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpCalendarVisual(tester, fake, settle: false);
    await tester.pump(const Duration(milliseconds: 700));
    await _screenshotCurrentFrame(tester, 'calendar_loading');
  });

  testWidgets('calendar_error: failed range query', (tester) async {
    _setMobileViewport(tester);
    final fake = _ErrorVisualCalendarBridge();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpCalendarVisual(tester, fake);
    await _screenshot(tester, 'calendar_error');
  });

  testWidgets('calendar_dual_occurrence: due and scheduled stay distinct', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData());
    expect(find.text('Prepare dual-occurrence review'), findsNWidgets(2));
    await _screenshot(tester, 'calendar_dual_occurrence');
  });

  testWidgets('calendar_datetime_zone: saved IANA deadline context', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarDateTimeZoneVisualData());
    await _screenshot(tester, 'calendar_datetime_zone');
  });

  testWidgets('calendar_move_sheet: accessible date-change alternative', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarVisualData());
    await tester.tap(find.byIcon(LucideIcons.calendarCog300).first);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'calendar_move_sheet');
  });

  testWidgets('calendar_completion_midframe: retained halo and strike', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpCalendarVisual(tester, await _calendarCompletedVisualData());
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'calendar-occurrence-check-task-0:date_due:',
            ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('task-completion-halo')), findsOneWidget);
    await _screenshotCurrentFrame(tester, 'calendar_completion_midframe');
  });

  testWidgets('search_empty: immersive empty-query state', (tester) async {
    _setMobileViewport(tester);
    await _pumpSearchVisual(tester, await _searchVisualData());
    await _screenshot(tester, 'search_empty');
  });

  testWidgets('search_loading: quiet in-progress state', (tester) async {
    _setMobileViewport(tester);
    final fake = _PendingVisualSearchBridge();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpSearchVisual(tester, fake, query: 'review', settle: false);
    await tester.pump(const Duration(milliseconds: 80));
    await _screenshotCurrentFrame(tester, 'search_loading');
  });

  testWidgets('search_results: active results with title and note', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpSearchVisual(tester, await _searchVisualData(), query: 'review');
    await _screenshot(tester, 'search_results');
  });

  testWidgets('search_zero: explicit no-result state', (tester) async {
    _setMobileViewport(tester);
    await _pumpSearchVisual(
      tester,
      await _searchVisualData(),
      query: 'unfindable',
    );
    await _screenshot(tester, 'search_zero');
  });

  testWidgets('search_error: recoverable search failure', (tester) async {
    _setMobileViewport(tester);
    final fake = _ErrorVisualSearchBridge();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    await _pumpSearchVisual(tester, fake, query: 'review');
    await _screenshot(tester, 'search_error');
  });

  testWidgets('search_archived_closed: archived list and closed statuses', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _pumpSearchVisual(
      tester,
      await _searchVisualData(),
      query: 'archive',
    );
    await _screenshot(tester, 'search_archived_closed');
  });

  testWidgets('search_narrow_320: results at 320px', (tester) async {
    _setNarrowViewport(tester);
    await _pumpSearchVisual(tester, await _searchVisualData(), query: 'review');
    await _screenshot(tester, 'search_narrow_320');
  });

  testWidgets('search_text_scale_2: results at Dynamic Type 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    await _pumpSearchVisual(tester, await _searchVisualData(), query: 'review');
    await _screenshot(tester, 'search_text_scale_2');
  });

  testWidgets('search_ja: localized result context', (tester) async {
    _setMobileViewport(tester);
    _useJaLocale(tester);
    await _pumpSearchVisual(tester, await _searchVisualData(), query: 'レビュー');
    await _screenshot(tester, 'search_ja');
  });

  testWidgets('search_rtl: directional padding and actions mirror', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final fake = await _searchVisualData();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeServiceProvider.overrideWithValue(fake),
          taskSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTodoriTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'review');
    await tester.pumpAndSettle();
    await _screenshot(tester, 'search_rtl');
  });

  testWidgets('quick_add_home_normal: Home quick add bar', (tester) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await _screenshot(tester, 'quick_add_home_normal');
  });

  testWidgets('task_create_sheet_home: Home task create sheet', (tester) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await _openTaskCreateSheetWithKeyboard(tester);
    await _screenshot(tester, 'task_create_sheet_home');
  });

  testWidgets('task_create_sheet_ja: Japanese task capture properties', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useJaLocale(tester);
    await _seedRealisticData(tester);
    await _openTaskCreateSheetWithKeyboard(tester);
    await _screenshot(tester, 'task_create_sheet_ja');
  });

  testWidgets('task_create_plan_sheet: planned start and estimate controls', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('task-create-plan-property-row')),
    );
    await tester.tap(
      find.byKey(const ValueKey('task-create-plan-property-row')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-45')));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_create_plan_sheet');
  });

  testWidgets('task_create_priority_sheet: calm priority selection', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('task-create-priority-property-row')),
    );
    await tester.tap(
      find.byKey(const ValueKey('task-create-priority-property-row')),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_create_priority_sheet');
  });

  testWidgets(
    'task_create_sheet_home_text_scale_2: Home create sheet at Dynamic Type 2.0',
    (tester) async {
      _setMobileViewport(tester);
      _useTextScale(tester, 2.0);
      await _seedRealisticData(tester);
      await _openTaskCreateSheetWithKeyboard(tester);
      await _screenshot(tester, 'task_create_sheet_home_text_scale_2');
    },
  );

  testWidgets('task_create_sheet_home_narrow_320: Home create sheet at 320px', (
    tester,
  ) async {
    _setNarrowViewport(tester);
    await _seedRealisticData(tester);
    await _openTaskCreateSheetWithKeyboard(tester);
    await _screenshot(tester, 'task_create_sheet_home_narrow_320');
  });

  testWidgets('task_create_plan_sheet_narrow_320: Plan sheet at 320px', (
    tester,
  ) async {
    _setNarrowViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('task-create-plan-property-row')),
      delta: 120,
    );
    await tester.tap(
      find.byKey(const ValueKey('task-create-plan-property-row')),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_create_plan_sheet_narrow_320');
  });

  testWidgets('task_create_plan_sheet_text_scale_2: Plan at text scale 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    await _seedRealisticData(tester);
    await tester.tap(find.byKey(const ValueKey('quick-add-open')));
    await tester.pumpAndSettle();
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('task-create-plan-property-row')),
      delta: 140,
    );
    await tester.tap(
      find.byKey(const ValueKey('task-create-plan-property-row')),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_create_plan_sheet_text_scale_2');
  });

  testWidgets('quick_add_list_normal: list quick add bar', (tester) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'quick_add_list_normal');
  });

  testWidgets('task_create_sheet_list: list task create sheet', (tester) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    await _openTaskCreateSheetWithKeyboard(tester);
    await _screenshot(tester, 'task_create_sheet_list');
  });

  testWidgets('task_swipe_complete_leading: leading complete action exposed', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.drag(find.text('地図アプリのUI微調整を仕上げる'), const Offset(280, 0));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_swipe_complete_leading');
  });

  testWidgets('task_swipe_focus_trailing: trailing Focus action exposed', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.drag(find.text('地図アプリのUI微調整を仕上げる'), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(find.text('Focus'), findsWidgets);
    await _screenshot(tester, 'task_swipe_focus_trailing');
  });

  testWidgets('task_due_mode_sheet: date-only and exact deadline choices', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, '地図アプリのUI微調整を仕上げる');
    final dueProperty = find.byKey(
      ValueKey('task-due-chip-${seed.focusTaskId}'),
    );
    await _ensureVisible(tester, dueProperty);
    await tester.tap(dueProperty);
    await tester.pumpAndSettle();
    expect(find.text('Set date'), findsOneWidget);
    expect(find.text('Set date and time'), findsOneWidget);
    await _screenshot(tester, 'task_due_mode_sheet');
  });

  testWidgets(
    'completion_motion_midframe: check halo and animated strikethrough',
    (tester) async {
      _setMobileViewport(tester);
      var isDone = false;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTodoriTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  final theme = Theme.of(context);
                  final colorScheme = theme.colorScheme;
                  return SizedBox(
                    width: 260,
                    child: Row(
                      children: [
                        AppTaskCheckbox(
                          checkboxKey: const ValueKey('visual-motion-checkbox'),
                          isDone: isDone,
                          tooltip: 'Toggle visual motion task',
                          onToggleDone: () => setState(() => isDone = !isDone),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AppAnimatedTaskTitle(
                            'Confirm final copy in the hero panel',
                            isDone: isDone,
                            maxLines: 2,
                            style: theme.textTheme.titleMedium?.copyWith(
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDone
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onSurface,
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
      await tester.tap(find.byKey(const ValueKey('visual-motion-checkbox')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await _screenshotCurrentFrame(tester, 'completion_motion_midframe');
      await tester.pump(const Duration(milliseconds: 210));
      await _screenshotCurrentFrame(tester, 'completion_motion_endframe');
      await tester.pumpAndSettle();
      await _screenshotCurrentFrame(tester, 'completion_motion_static');
    },
  );

  testWidgets('wont_do_row: closed section with a wont_do row', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final today = _todayStartMs();
    await fake.createTask(
      listId: listId,
      title: 'Review launch brief',
      due: testDateOnlyDueFromMillis(today),
    );
    final skipped = await fake.createTask(
      listId: listId,
      title: 'Replace the planning spreadsheet',
      due: testDateOnlyDueFromMillis(today),
    );
    await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');
    final done = await fake.createTask(
      listId: listId,
      title: 'Send weekly notes',
      due: testDateOnlyDueFromMillis(today),
    );
    await fake.setTaskStatus(taskId: done.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'wont_do_row');
  });

  testWidgets('task_list_reorder_dragging: manual reorder drag state', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    final source = find.text('地図アプリのUI微調整を仕上げる');
    final target = find.text(seed.parentWithSubtasksTitle);
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getRect(target).bottomCenter.translate(0, -4));
    await tester.pump();
    await _screenshot(tester, 'task_list_reorder_dragging');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('lists: list management screen with two lists', (tester) async {
    _setMobileViewport(tester);
    await _seedArchivedListData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists');
  });

  testWidgets('lists_text_scale_2: list management at Dynamic Type 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    await _seedArchivedListData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists_text_scale_2');
  });

  testWidgets('lists_archived: archived section expanded', (tester) async {
    _setMobileViewport(tester);
    await _seedArchivedListData(tester);
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists_archived');
  });

  testWidgets('account_signed_out: account screen with server URL form', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedArchivedListData(tester);
    await tester.tap(find.text('You').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'account_signed_out');
  });

  testWidgets('list_actions_menu: opened list overflow menu', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final work = await fake.createList(name: '仕事', sortOrder: 'a1');
    await fake.createTask(listId: work.id, title: '四半期レビュー資料を作成する');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('仕事'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'list_actions_menu');
  });

  testWidgets('task_detail: parent detail with a three-level subtree', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await _screenshot(tester, 'task_detail');
  });

  testWidgets('task_detail_text_scale_2: detail at Dynamic Type 2.0', (
    tester,
  ) async {
    _setMobileViewport(tester);
    _useTextScale(tester, 2.0);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await _screenshot(tester, 'task_detail_text_scale_2');
  });

  testWidgets('task_detail_plan_sheet: task planning from detail', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    final planRow = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('task-plan-row-'),
    );
    await _ensureVisible(tester, planRow);
    await tester.tap(planRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-estimate-preset-25')));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_detail_plan_sheet');
  });

  testWidgets('task_detail_editing: inline title editing on task detail', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await tester.tap(find.text(seed.parentWithSubtasksTitle));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_detail_editing');
  });

  testWidgets('delete_task_confirm: permanent task delete warning', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await tester.tap(find.byTooltip('Task actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'delete_task_confirm');
  });

  testWidgets('delete_list_confirm: permanent list delete warning', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final work = await fake.createList(name: 'Work', sortOrder: 'a1');
    await fake.createTask(listId: work.id, title: 'Completed planning note');
    final done = await fake.createTask(listId: work.id, title: 'Done task');
    await fake.setTaskStatus(taskId: done.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lists').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await _screenshot(tester, 'delete_list_confirm');
  });

  testWidgets('confirm_dialog: completing a parent with an open subtask', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Ship the release notes',
      due: testDateOnlyDueFromMillis(_todayStartMs()),
    );
    await fake.createTask(
      listId: listId,
      title: 'Proofread release notes with the docs team',
      parentTaskId: parent.id,
    );

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('task-done-${parent.id}')));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'confirm_dialog');
  });

  testWidgets('design_lab_task_list: single-canvas Today direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskList),
    );
    await _screenshot(tester, 'design_lab_task_list');
  });

  testWidgets('design_lab_calendar: quiet completed reflection', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.calendar),
    );
    await _screenshot(tester, 'design_lab_calendar');
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'design_lab_calendar_completed');
  });

  testWidgets('design_lab_list_overview: borderless list index direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.listOverview),
    );
    await _screenshot(tester, 'design_lab_list_overview');
  });

  testWidgets('design_lab_focus_timer: dark horizon focus direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.focusTimer),
    );
    await _precacheDesignLabMascot(tester);
    await _screenshot(tester, 'design_lab_focus_timer');
  });

  testWidgets('design_lab_task_detail: single-canvas document direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskDetail),
    );
    await _screenshot(tester, 'design_lab_task_detail');
  });

  testWidgets('design_lab_task_create_sheet: minimal task capture direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskCreateSheet),
    );
    await _screenshot(tester, 'design_lab_task_create_sheet');
  });

  testWidgets('design_lab_completion_midframe: halo and strike', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(const InteractiveDesignLabApp());
    await tester.tap(
      find.byKey(
        const ValueKey('design-lab-task-check-Review onboarding copy'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await _screenshotCurrentFrame(tester, 'design_lab_completion_midframe');
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pump(const Duration(milliseconds: 180));
    await _screenshotCurrentFrame(
      tester,
      'design_lab_completion_collapse_midframe',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('design_lab_search: underline search direction', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(const DesignLabMockApp(mock: DesignLabMock.search));
    await _screenshot(tester, 'design_lab_search');
  });

  testWidgets('design_lab_settings: borderless account direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.settings),
    );
    await _screenshot(tester, 'design_lab_settings');
  });

  testWidgets('design_lab_timer_setup: typographic focus setup direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.timerSetup),
    );
    await _screenshot(tester, 'design_lab_timer_setup');
  });

  testWidgets('design_lab_list_tasks: a full list in the shared task grammar', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.listTasks),
    );
    await _screenshot(tester, 'design_lab_list_tasks');
    final menuPress = await tester.startGesture(
      tester.getCenter(find.byIcon(LucideIcons.moreHorizontal300)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await _screenshot(tester, 'design_lab_list_tasks_menu_press');
    await menuPress.up();
    await tester.pumpAndSettle();
    await tester.drag(find.text('Prepare launch notes'), const Offset(-90, 0));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'design_lab_list_tasks_timer_reveal');
  });

  testWidgets('design_lab_task_detail_editing: calm document editing', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskDetailEditing),
    );
    await _screenshot(tester, 'design_lab_task_detail_editing');
  });

  testWidgets('design_lab_account_signed_out: private account access', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.accountSignedOut),
    );
    await _screenshot(tester, 'design_lab_account_signed_out');
  });

  testWidgets('design_lab_task_actions: safe action sheet composition', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskActions),
    );
    await _screenshot(tester, 'design_lab_task_actions');
  });

  testWidgets('design_lab_due_date_sheet: quick scheduling choices', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.dueDateSheet),
    );
    await _screenshot(tester, 'design_lab_due_date_sheet');
  });

  testWidgets('design_lab_system_states: empty loading and error grammar', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.systemStates),
    );
    await _screenshot(tester, 'design_lab_system_states');
  });

  testWidgets('design_lab_onboarding: quiet first-run direction', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.onboarding),
    );
    await _screenshot(tester, 'design_lab_onboarding');
  });

  // Typography comparison: 4 variants x 2 screens (Today task list, Focus
  // timer). See `docs/design/ui-spec.md` セクション6 note and
  // `design_lab_mocks.dart`'s `DesignLabTypoVariant`/`DesignLabTypography`.
  for (final variant in DesignLabTypoVariant.values) {
    final variantId = _typoVariantIds[variant]!;
    if (variant == DesignLabTypoVariant.jaMinchoD &&
        !_zenOldMinchoFontAvailable) {
      test(
        'design_lab_typo_$variantId: skipped, Zen Old Mincho font not '
        'available',
        () {},
        skip:
            'Run `sh tool/fetch_lab_fonts.sh` (or `sh tool/visual_qa.sh`, '
            'which calls it first) with network access to download Zen Old '
            'Mincho to $_zenOldMinchoFontPath; D案 screenshots are skipped '
            'without it.',
      );
      continue;
    }
    for (final screen in DesignLabTypoScreen.values) {
      final screenId = _typoScreenIds[screen]!;
      final name = 'design_lab_typo_${variantId}_$screenId';
      testWidgets('$name: typography comparison', (tester) async {
        _setMobileViewport(tester);
        await tester.pumpWidget(
          DesignLabTypoMockApp(variant: variant, screen: screen),
        );
        await _screenshot(tester, name);
      });
    }
  }
}

enum _FocusVisualState { setup, running, paused, finished }

Future<void> _pumpFocusVisual(
  WidgetTester tester, {
  _FocusVisualState state = _FocusVisualState.setup,
  String taskTitle = 'Shape the next release with care',
}) async {
  final fake = FakeBridgeService();
  await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final listId = (await fake.getLists()).single.id;
  final task = await fake.createTask(
    listId: listId,
    title: taskTitle,
    estimatedMinutes: 25,
  );
  final clock = _VisualTimerClock(DateTime.utc(2026, 7, 13, 9));
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
  if (state == _FocusVisualState.setup) {
    return;
  }
  final start = find.byKey(const ValueKey('focus-start'));
  await tester.scrollUntilVisible(start, 160);
  await tester.tap(start);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  if (state == _FocusVisualState.paused) {
    clock.advance(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('focus-pause')));
    for (var attempt = 0; attempt < 4; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 80));
      if (find.byKey(const ValueKey('focus-paused')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('focus-paused')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('focus-screen')),
    );
    expect(scaffold.backgroundColor, AppFocusColors.surface);
    expect(
      tester.getSize(find.byKey(const ValueKey('focus-screen'))),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    // The paused key appears on the first rebuild, before the pressed-state
    // ink and inherited theme repaint have necessarily completed. Capture a
    // stable post-transition frame so batch Visual QA cannot retain a partial
    // transparent surface from the preceding running case.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  } else if (state == _FocusVisualState.finished) {
    clock.advance(const Duration(minutes: 12));
    await tester.tap(find.byKey(const ValueKey('focus-finish')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('focus-finished')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('focus-screen')),
    );
    expect(scaffold.backgroundColor, AppColors.canvas);
    expect(
      tester.getSize(find.byKey(const ValueKey('focus-screen'))),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }
}

class _VisualTimerClock implements TimerClock {
  _VisualTimerClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

Future<void> _pumpRestoredFocusVisual(WidgetTester tester) async {
  final fake = FakeBridgeService();
  await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final listId = (await fake.getLists()).single.id;
  final task = await fake.createTask(
    listId: listId,
    title: 'Continue the restored focus session',
    estimatedMinutes: 25,
  );
  final now = DateTime.now().toUtc();
  await fake.startActiveTimerSession(
    session: ActiveTimerSessionDto(
      sessionId: '00000000-0000-4000-8000-000000000106',
      taskId: task.id,
      mode: TimerModeDto.stopwatch,
      phase: TimerPhaseDto.work,
      state: TimerRunStateDto.running,
      startedAt: now.subtract(const Duration(minutes: 5)),
      lastResumedAt: now.subtract(const Duration(minutes: 5)),
      accumulatedActiveMs: 0,
    ),
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
  for (var attempt = 0; attempt < 10; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byKey(const ValueKey('focus-running')).evaluate().isNotEmpty) {
      break;
    }
  }
  expect(find.byKey(const ValueKey('focus-running')), findsOneWidget);
}

Future<void> _pumpFocusErrorVisual(WidgetTester tester) async {
  final fake = _FocusErrorVisualBridge();
  await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final listId = (await fake.getLists()).single.id;
  final task = await fake.createTask(
    listId: listId,
    title: 'Recover the focus session',
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
  final errorText = find.text("Todori couldn't restore this focus session.");
  for (var attempt = 0; attempt < 10; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (errorText.evaluate().isNotEmpty) {
      break;
    }
  }
  expect(errorText, findsOneWidget);
}

class _FocusErrorVisualBridge extends FakeBridgeService {
  @override
  Future<ActiveTimerSessionDto?> getActiveTimerSession() {
    throw StateError('simulated timer restore failure');
  }
}

const _typoVariantIds = {
  DesignLabTypoVariant.newsreaderA: 'a_newsreader',
  DesignLabTypoVariant.loraB: 'b_lora',
  DesignLabTypoVariant.sansOnlyC: 'c_sans_only',
  DesignLabTypoVariant.jaMinchoD: 'd_ja_mincho',
};

const _typoScreenIds = {
  DesignLabTypoScreen.today: 'today',
  DesignLabTypoScreen.focus: 'focus',
};

/// Handles produced by [_seedRealisticData] so individual screenshot tests
/// can navigate to a specific seeded task without hardcoding titles twice.
class _SeedData {
  const _SeedData({
    required this.fake,
    required this.parentWithSubtasksTitle,
    required this.focusTaskId,
  });

  final FakeBridgeService fake;
  final String parentWithSubtasksTitle;
  final String focusTaskId;
}

/// Seeds two lists ("Inbox" as the home list, "仕事" as a second list) with a
/// realistic, mixed set of tasks and pumps [TodoriApp] on top of them:
///
/// - priorities: high, medium, low, and none all appear.
/// - due values: date-only, exact datetime with a foreign IANA zone, overdue,
///   today, tomorrow, upcoming, and no-due-date all appear.
/// - one task is already completed and one is closed as wont_do.
/// - one task ("Plan the product launch event") has three subtasks, one of
///   which is completed after an overdue due date.
/// - titles mix Japanese and English, and one title is long enough to wrap.
Future<_SeedData> _seedRealisticData(WidgetTester tester) async {
  final fake = FakeBridgeService();
  await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  await fake.createList(name: '仕事', sortOrder: 'a1');
  final lists = await fake.getLists();
  final homeListId = lists[0].id;
  final workListId = lists[1].id;

  DateTime atMidnight(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  final now = DateTime.now();
  final today = atMidnight(now).millisecondsSinceEpoch;
  final todayExact = DateTime(
    now.year,
    now.month,
    now.day,
    14,
    30,
  ).millisecondsSinceEpoch;
  final tomorrow = atMidnight(
    now.add(const Duration(days: 1)),
  ).millisecondsSinceEpoch;
  final overdue = atMidnight(
    now.subtract(const Duration(days: 4)),
  ).millisecondsSinceEpoch;
  final upcoming = atMidnight(
    now.add(const Duration(days: 5)),
  ).millisecondsSinceEpoch;

  final uiTweaks = await fake.createTask(
    listId: homeListId,
    title: '地図アプリのUI微調整を仕上げる',
  );
  await fake.updateTask(
    taskId: uiTweaks.id,
    title: uiTweaks.title,
    note: '',
    priority: 2,
    due: testDateTimeDueFromMillis(todayExact, timeZone: 'America/New_York'),
  );

  const parentWithSubtasksTitle = 'Plan the product launch event';
  final launch = await fake.createTask(
    listId: homeListId,
    title: parentWithSubtasksTitle,
  );
  await fake.updateTask(
    taskId: launch.id,
    title: launch.title,
    note: '',
    priority: 2,
    due: testDateOnlyDueFromMillis(tomorrow),
  );
  await fake.setTaskReminder(
    taskId: launch.id,
    remindAt: DateTime(
      now.year,
      now.month,
      now.day,
      16,
      30,
    ).millisecondsSinceEpoch,
  );
  final checklist = await fake.createTask(
    listId: homeListId,
    title: 'Draft the launch checklist',
    parentTaskId: launch.id,
  );
  await fake.updateTask(
    taskId: checklist.id,
    title: checklist.title,
    note: '',
    priority: 1,
    due: testDateOnlyDueFromMillis(today),
  );
  await fake.setTaskReminder(
    taskId: checklist.id,
    remindAt: DateTime(
      now.year,
      now.month,
      now.day,
      16,
      30,
    ).millisecondsSinceEpoch,
  );
  await fake.createTask(
    listId: homeListId,
    title: 'Review checklist with design',
    parentTaskId: launch.id,
  );
  final finalCopy = await fake.createTask(
    listId: homeListId,
    title: 'Confirm final copy in the hero panel',
    parentTaskId: checklist.id,
  );
  await fake.updateTask(
    taskId: finalCopy.id,
    title: finalCopy.title,
    note: '',
    priority: 0,
    due: testDateOnlyDueFromMillis(overdue),
  );
  await fake.setTaskStatus(taskId: finalCopy.id, status: 'done');
  await fake.createTask(
    listId: homeListId,
    title: 'デザインレビューのフィードバックを反映する',
    parentTaskId: launch.id,
  );

  const longTitle =
      'Draft the Q3 roadmap presentation for the leadership offsite meeting '
      'next week';
  final roadmap = await fake.createTask(listId: homeListId, title: longTitle);
  await fake.updateTask(
    taskId: roadmap.id,
    title: roadmap.title,
    note: 'Include churn metrics and the hiring plan.',
    priority: 3,
    due: testDateOnlyDueFromMillis(upcoming),
  );

  final groceries = await fake.createTask(
    listId: homeListId,
    title: '買い物リストを整理する',
  );
  await fake.updateTask(
    taskId: groceries.id,
    title: groceries.title,
    note: '',
    priority: 1,
    due: null,
  );

  final planning = await fake.createTask(
    listId: homeListId,
    title: 'Plan July archive review',
  );
  await fake.updateTask(
    taskId: planning.id,
    title: planning.title,
    note: '',
    priority: 1,
    due: testDateOnlyDueFromMillis(upcoming),
  );

  final passport = await fake.createTask(
    listId: homeListId,
    title: 'Renew passport before the trip',
  );
  await fake.updateTask(
    taskId: passport.id,
    title: passport.title,
    note: '',
    priority: 0,
    due: testDateOnlyDueFromMillis(overdue),
  );

  final standup = await fake.createTask(listId: homeListId, title: '朝会に参加する');
  await fake.updateTask(
    taskId: standup.id,
    title: standup.title,
    note: '',
    priority: 0,
    due: testDateOnlyDueFromMillis(today),
  );
  await fake.setTaskStatus(taskId: standup.id, status: 'done');

  final skipped = await fake.createTask(
    listId: homeListId,
    title: 'Replace the planning spreadsheet',
  );
  await fake.updateTask(
    taskId: skipped.id,
    title: skipped.title,
    note: '',
    priority: 0,
    due: null,
  );
  await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');

  final workReview = await fake.createTask(
    listId: workListId,
    title: '四半期レビュー資料を作成する',
  );
  await fake.updateTask(
    taskId: workReview.id,
    title: workReview.title,
    note: '',
    priority: 3,
    due: testDateOnlyDueFromMillis(today),
  );

  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();

  return _SeedData(
    fake: fake,
    parentWithSubtasksTitle: parentWithSubtasksTitle,
    focusTaskId: uiTweaks.id,
  );
}

int _todayStartMs() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
}

Future<FakeBridgeService> _searchVisualData() async {
  final fake = FakeBridgeService();
  final inbox = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final archive = await fake.createList(name: 'Archive', sortOrder: 'a1');
  await fake.createTask(
    listId: inbox.id,
    title: 'Review the release outline',
    note: 'Keep the launch sequence calm and concise.',
    priority: 3,
  );
  await fake.createTask(
    listId: inbox.id,
    title: 'レビューのフィードバックを反映する',
    note: '次のリリースに向けて要点を整理。',
    priority: 2,
  );
  final done = await fake.createTask(
    listId: archive.id,
    title: 'Archive review decisions',
    note: 'Final notes from the completed review.',
  );
  final skipped = await fake.createTask(
    listId: archive.id,
    title: 'Archive review alternative',
  );
  await fake.setTaskStatus(taskId: done.id, status: 'done');
  await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');
  await fake.archiveList(listId: archive.id);
  return fake;
}

Future<void> _pumpSearchVisual(
  WidgetTester tester,
  FakeBridgeService fake, {
  String? query,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    TodoriApp(
      overrides: [
        bridgeServiceProvider.overrideWithValue(fake),
        taskSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final englishSearch = find.byTooltip('Search tasks');
  final searchAction = englishSearch.evaluate().isNotEmpty
      ? englishSearch
      : find.byTooltip('タスクを検索');
  await tester.tap(searchAction);
  await tester.pumpAndSettle();
  if (query != null) {
    await tester.enterText(find.byType(TextField), query);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}

class _PendingVisualSearchBridge extends FakeBridgeService {
  final Completer<List<TaskDto>> _pending = Completer<List<TaskDto>>();

  @override
  Future<List<TaskDto>> searchTasks({required String query}) => _pending.future;
}

class _ErrorVisualSearchBridge extends FakeBridgeService {
  @override
  Future<List<TaskDto>> searchTasks({required String query}) =>
      Future<List<TaskDto>>.error(StateError('visual search failure'));
}

Future<FakeBridgeService> _calendarVisualData() async {
  final fake = FakeBridgeService();
  final inbox = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final archive = await fake.createList(name: 'Archive', sortOrder: 'a1');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayAt = DateTime(
    now.year,
    now.month,
    now.day,
    10,
    30,
  ).millisecondsSinceEpoch;
  final tomorrow = DateTime(now.year, now.month, now.day + 1);

  await fake.createTask(
    listId: inbox.id,
    title: 'Finish the calendar interaction pass',
    due: testDateOnlyDueFromMillis(today.millisecondsSinceEpoch),
    priority: 3,
  );
  await fake.createTask(
    listId: inbox.id,
    title: 'Prepare dual-occurrence review',
    due: testDateOnlyDueFromMillis(today.millisecondsSinceEpoch),
    scheduledAt: todayAt,
    priority: 2,
  );
  await fake.createTask(
    listId: inbox.id,
    title: 'Scheduled design critique',
    scheduledAt: DateTime(
      now.year,
      now.month,
      now.day,
      15,
    ).millisecondsSinceEpoch,
    priority: 1,
  );
  await fake.createTask(
    listId: inbox.id,
    title: 'Tomorrow roadmap handoff',
    due: testDateOnlyDueFromMillis(tomorrow.millisecondsSinceEpoch),
  );
  final parent = await fake.createTask(
    listId: inbox.id,
    title: 'Calendar launch checklist',
    due: testDateOnlyDueFromMillis(today.millisecondsSinceEpoch),
  );
  await fake.createTask(
    listId: inbox.id,
    parentTaskId: parent.id,
    title: 'Verify tree connector spacing',
    due: testDateOnlyDueFromMillis(today.millisecondsSinceEpoch),
  );
  final completed = await fake.createTask(
    listId: inbox.id,
    title: 'Completed calendar contract',
    due: testDateOnlyDueFromMillis(today.millisecondsSinceEpoch),
  );
  await fake.setTaskStatus(taskId: completed.id, status: 'done');
  await fake.createTask(
    listId: archive.id,
    title: 'Archived milestone context',
    due: testDateOnlyDueFromMillis(today.millisecondsSinceEpoch),
  );
  await fake.archiveList(listId: archive.id);
  return fake;
}

Future<FakeBridgeService> _calendarCompletedVisualData() async {
  final fake = FakeBridgeService();
  final inbox = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  await fake.createTask(
    listId: inbox.id,
    title: 'Review today agenda',
    due: testDateOnlyDueFromMillis(today),
    priority: 2,
  );
  final completed = await fake.createTask(
    listId: inbox.id,
    title: 'Completed range contract',
    due: testDateOnlyDueFromMillis(today),
  );
  await fake.setTaskStatus(taskId: completed.id, status: 'done');
  return fake;
}

Future<FakeBridgeService> _calendarDateTimeZoneVisualData() async {
  final fake = FakeBridgeService();
  final inbox = await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final now = DateTime.now();
  final deadline = DateTime(now.year, now.month, now.day, 18, 45);
  await fake.createTask(
    listId: inbox.id,
    title: 'New York partner deadline',
    due: testDateTimeDueFromMillis(
      deadline.millisecondsSinceEpoch,
      timeZone: 'America/New_York',
    ),
    priority: 2,
  );
  return fake;
}

Future<void> _pumpCalendarVisual(
  WidgetTester tester,
  FakeBridgeService fake, {
  bool month = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(LucideIcons.calendarDays300).last);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  if (month) {
    await tester.tap(find.byKey(const ValueKey('calendar-mode-month')));
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpCalendarVisualRtl(
  WidgetTester tester,
  FakeBridgeService fake,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTodoriTheme(Brightness.light),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: CalendarScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _PendingVisualCalendarBridge extends FakeBridgeService {
  final Completer<List<CalendarOccurrenceDto>> _pending =
      Completer<List<CalendarOccurrenceDto>>();

  @override
  Future<List<CalendarOccurrenceDto>> getCalendarOccurrences({
    required CalendarRangeInput range,
  }) => _pending.future;
}

class _ErrorVisualCalendarBridge extends FakeBridgeService {
  @override
  Future<List<CalendarOccurrenceDto>> getCalendarOccurrences({
    required CalendarRangeInput range,
  }) => Future<List<CalendarOccurrenceDto>>.error(
    StateError('visual calendar failure'),
  );
}

String _visualCivilDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Future<void> _seedArchivedListData(WidgetTester tester) async {
  final fake = FakeBridgeService();
  await fake.createDefaultList(name: 'Inbox', sortOrder: 'a0');
  final work = await fake.createList(name: '仕事', sortOrder: 'a1');
  await fake.createTask(listId: work.id, title: '四半期レビュー資料を作成する');
  await fake.archiveList(listId: work.id);

  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [title] into view (if needed) and taps it to open task detail.
///
/// Uses [WidgetTester.scrollUntilVisible] rather than [ensureVisible]
/// because the home task list may not have built (and thus cannot find) an
/// item that is entirely below the fold yet.
Future<void> _openTask(WidgetTester tester, String title) async {
  final titleFinder = find.text(title);
  for (var attempts = 0; attempts < 12; attempts++) {
    final visibleTitle = titleFinder.hitTestable();
    if (tester.any(visibleTitle)) {
      await tester.tap(visibleTitle.first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(titleFinder.first);
  await tester.pumpAndSettle();
  await tester.tap(titleFinder.hitTestable().first);
  await tester.pumpAndSettle();
}

void _setMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = Size(
    _mobileLogicalSize.width * _mobileDevicePixelRatio,
    _mobileLogicalSize.height * _mobileDevicePixelRatio,
  );
  tester.view.devicePixelRatio = _mobileDevicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _setNarrowViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(960, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _setWideViewport(WidgetTester tester) {
  tester.view.physicalSize = Size(
    _wideLogicalSize.width * _wideDevicePixelRatio,
    _wideLogicalSize.height * _wideDevicePixelRatio,
  );
  tester.view.devicePixelRatio = _wideDevicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _setLogicalViewport(
  WidgetTester tester,
  Size logicalSize, {
  required double devicePixelRatio,
}) {
  tester.view.physicalSize = Size(
    logicalSize.width * devicePixelRatio,
    logicalSize.height * devicePixelRatio,
  );
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _useTextScale(WidgetTester tester, double textScaleFactor) {
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _openTaskCreateSheetWithKeyboard(WidgetTester tester) async {
  final keyboardInset = 300 * tester.view.devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.resetViewInsets);
  await tester.tap(find.byKey(const ValueKey('quick-add-open')));
  await tester.pumpAndSettle();
}

Future<void> _ensureVisible(
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
  } else if (!tester.any(finder.hitTestable())) {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        Offset(0, -delta),
      );
      await tester.pumpAndSettle();
      if (tester.any(finder.hitTestable())) {
        break;
      }
    }
  }
  await tester.pumpAndSettle();
}

void _useDarkPlatformBrightness(WidgetTester tester) {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Forces the ja locale so `home_tasks_ja` renders Japanese UI strings (and,
/// per the 2026-07-06 typography ruling, the "今日" Today heading through
/// the `Hiragino Mincho ProN` serif fallback registered in
/// [_loadMinchoFallbackFont]).
void _useJaLocale(WidgetTester tester) {
  tester.platformDispatcher.localeTestValue = const Locale('ja');
  tester.platformDispatcher.localesTestValue = const [Locale('ja')];
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// Rasterizes the whole app (including any open dialog/overlay) to a PNG at
/// `build/visual_qa/$name.png`. Deliberately does *not* use
/// [matchesGoldenFile]; there is no reference image to diff against, this is
/// a one-way export for human review.
Future<void> _screenshot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await _writeScreenshot(tester, name);
}

Future<void> _precacheDesignLabMascot(WidgetTester tester) async {
  final context = tester.element(find.byType(MaterialApp));
  await tester.runAsync(
    () => precacheImage(
      const AssetImage(
        'assets/brand/generated/todori-mascot-ui-sprites-v1.png',
      ),
      context,
    ),
  );
  await tester.pump();
}

Future<void> _screenshotCurrentFrame(WidgetTester tester, String name) async {
  await _writeScreenshot(tester, name);
}

Future<void> _writeScreenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final element = tester.element(find.byType(MaterialApp));
    final image = await captureImage(element);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed to encode $name.png as PNG.');
      }
      final directory = Directory(_outputDir);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File('${directory.path}/$name.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// Loads real fonts so screenshots show legible glyphs instead of the
/// "tofu" boxes `flutter test` renders by default.
///
/// - Material Icons come from the Flutter SDK cache (`$FLUTTER_ROOT`), so
///   icon glyphs (checkboxes, chevrons, the FAB `+`, etc.) render correctly.
/// - Lucide Icons come from the hosted package cache and are registered under
///   the package-qualified font family used by `IconData(fontPackage: ...)`.
/// - The bundled brand typefaces (`assets/fonts/Newsreader`,
///   `assets/fonts/Inter`; see `app/pubspec.yaml` `fonts:` and
///   `docs/design/ui-spec.md` セクション2) are registered under their real
///   family names, each weight in turn, so the Today heading serif
///   (Newsreader) and UI body sans (Inter) render as designed instead of
///   falling back to the test harness's tofu boxes. `assets/fonts/Lora` is
///   also registered (see [_loraWeightPaths]) purely for the Design Lab B案
///   comparison screenshots -- it is intentionally not declared in
///   `app/pubspec.yaml` `fonts:` since Lora is decommissioned from the
///   shipped app (2026-07-06 typography ruling).
/// - Two macOS system fonts that can render Japanese glyphs are registered:
///   a gothic one under the `Hiragino Sans` family (used as the fallback for
///   every Inter text role) and a serif one under the `Hiragino Mincho
///   ProN` family (used only as the fallback for the Newsreader Today
///   heading) -- the same names `theme.dart` declares in each style's
///   `fontFamilyFallback` -- so mixed Japanese/English seed data resolves
///   Japanese glyphs through those *separate* families instead of tofu.
///
///   (Registering the Japanese font as extra same-family candidates on
///   'Inter'/'Newsreader' directly, as `FontLoader`'s docs suggest is
///   possible, was tried first and did not work here: once a family has
///   multiple candidates of different declared weights, Skia's style
///   matching picks the closest-weight *Latin* candidate for a run and does
///   not appear to retry sibling candidates in that family for glyphs it
///   lacks. Routing Japanese through `fontFamilyFallback` -- a separate,
///   single-typeface family that Flutter tries per missing glyph -- is what
///   actually renders Japanese here.)
Future<void> _loadRealFonts() async {
  await _loadMaterialIconsFont();
  await _loadLucideIconsFont();
  await _loadBrandFont(family: 'Inter', weightPaths: _interWeightPaths);
  await _loadBrandFont(family: 'Lora', weightPaths: _loraWeightPaths);
  await _loadBrandFont(
    family: 'Newsreader',
    weightPaths: _newsreaderWeightPaths,
  );
  await _loadBrandFont(
    family: 'SourceSerif4',
    weightPaths: _sourceSerif4WeightPaths,
  );
  await _loadZenOldMinchoFont();
  await _loadCjkFallbackFont();
  await _loadMinchoFallbackFont();
}

/// Loads the Design Lab-only Zen Old Mincho font (D案 Today heading) if
/// `tool/fetch_lab_fonts.sh` has downloaded it. Never committed to the repo
/// (see `docs/design/ui-spec.md` セクション6); the
/// `design_lab_typo_d_ja_mincho_*` tests skip themselves via
/// [_zenOldMinchoFontAvailable] when this file is missing.
Future<void> _loadZenOldMinchoFont() async {
  if (!_zenOldMinchoFontAvailable) {
    return;
  }
  final loader = FontLoader('ZenOldMincho');
  await _addFontFile(loader, _zenOldMinchoFontPath);
  await loader.load();
}

const _interWeightPaths = [
  'assets/fonts/Inter/Inter-Regular.ttf',
  'assets/fonts/Inter/Inter-Medium.ttf',
  'assets/fonts/Inter/Inter-SemiBold.ttf',
  'assets/fonts/Inter/Inter-Bold.ttf',
];

const _loraWeightPaths = [
  'assets/fonts/Lora/Lora-Regular.ttf',
  'assets/fonts/Lora/Lora-Medium.ttf',
  'assets/fonts/Lora/Lora-SemiBold.ttf',
  'assets/fonts/Lora/Lora-Bold.ttf',
];

const _newsreaderWeightPaths = [
  'assets/fonts/Newsreader/Newsreader-Regular.ttf',
  'assets/fonts/Newsreader/Newsreader-Medium.ttf',
  'assets/fonts/Newsreader/Newsreader-SemiBold.ttf',
];

/// Design Lab-only candidate replacing Newsreader in the compact product
/// direction. A variable font is sufficient because the exploration uses a
/// single restrained medium weight for display text and timer numerals.
const _sourceSerif4WeightPaths = [
  'assets/fonts/SourceSerif4/SourceSerif4-Variable.ttf',
];

/// Must match the first entry of `_cjkFontFamilyFallback` in
/// `lib/src/ui/theme.dart`.
const _cjkFallbackFamily = 'Hiragino Sans';

/// Japanese-capable system fonts to try for [_cjkFallbackFamily], in
/// preference order (Hiragino first, Helvetica as a last resort so the
/// harness still runs on non-macOS CI without crashing, albeit with tofu for
/// Japanese in that case).
const _cjkFallbackPaths = [
  '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
  '/System/Library/Fonts/Helvetica.ttc',
];

Future<void> _loadMaterialIconsFont() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    return;
  }
  final loader = FontLoader('MaterialIcons');
  await _addFontFile(
    loader,
    '$flutterRoot/bin/cache/artifacts/material_fonts/'
    'MaterialIcons-Regular.otf',
  );
  await loader.load();
}

Future<void> _loadLucideIconsFont() async {
  final packageRoot = await _packageRootPath('lucide_icons_flutter');
  if (packageRoot == null) {
    return;
  }
  final fontPath = '$packageRoot/assets/build_font/LucideVariable-w300.ttf';
  for (final family in const [
    'packages/lucide_icons_flutter/Lucide300',
    'Lucide300',
  ]) {
    final loader = FontLoader(family);
    if (await _addFontFile(loader, fontPath)) {
      await loader.load();
    }
  }
}

Future<String?> _packageRootPath(String packageName) async {
  final packageConfigFile = File('.dart_tool/package_config.json');
  if (!packageConfigFile.existsSync()) {
    return null;
  }
  final config =
      jsonDecode(await packageConfigFile.readAsString())
          as Map<String, Object?>;
  final packages = config['packages'] as List<Object?>;
  for (final package in packages.cast<Map<String, Object?>>()) {
    if (package['name'] != packageName) {
      continue;
    }
    final rootUri = Uri.parse(package['rootUri']! as String);
    final resolvedRoot = rootUri.hasScheme
        ? rootUri
        : packageConfigFile.parent.uri.resolveUri(rootUri);
    return resolvedRoot.toFilePath();
  }
  return null;
}

/// Registers every bundled weight for [family] on **one** [FontLoader]
/// instance loaded exactly once.
Future<void> _loadBrandFont({
  required String family,
  required List<String> weightPaths,
}) async {
  final loader = FontLoader(family);
  for (final path in weightPaths) {
    await _addFontFile(loader, path);
  }
  await loader.load();
}

/// Registers a single Japanese-capable system font under
/// [_cjkFallbackFamily] -- a dedicated family with exactly one candidate, so
/// there is no competing same-family typeface to out-rank it (see the
/// [_loadRealFonts] doc comment for why that matters).
Future<void> _loadCjkFallbackFont() async {
  final loader = FontLoader(_cjkFallbackFamily);
  for (final path in _cjkFallbackPaths) {
    if (await _addFontFile(loader, path)) {
      break;
    }
  }
  await loader.load();
}

/// Must match the first entry of `_serifCjkFontFamilyFallback` in
/// `lib/src/ui/theme.dart` -- the Today heading's serif-specific Japanese
/// fallback (distinct from [_cjkFallbackFamily], which every other Inter
/// text role uses).
const _minchoFallbackFamily = 'Hiragino Mincho ProN';

/// macOS's bundled Japanese serif, used to render `home_tasks_ja`'s "今日"
/// Today heading in the serif fallback the production theme declares.
const _minchoFallbackPaths = ['/System/Library/Fonts/ヒラギノ明朝 ProN.ttc'];

/// Registers a single Japanese-capable serif system font under
/// [_minchoFallbackFamily] (see [_loadCjkFallbackFont] for why a dedicated,
/// single-candidate family is used).
Future<void> _loadMinchoFallbackFont() async {
  final loader = FontLoader(_minchoFallbackFamily);
  for (final path in _minchoFallbackPaths) {
    if (await _addFontFile(loader, path)) {
      break;
    }
  }
  await loader.load();
}

/// Reads [path] and adds it to [loader] if the file exists. Returns whether
/// the font was added, so callers can stop after the first available
/// candidate in a preference-ordered list (e.g. [_cjkFallbackPaths]).
Future<bool> _addFontFile(FontLoader loader, String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    return false;
  }
  final bytes = await file.readAsBytes();
  loader.addFont(
    Future.value(
      ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );
  return true;
}
