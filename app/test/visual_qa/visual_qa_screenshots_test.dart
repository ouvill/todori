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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/main.dart';
import 'package:todori/src/core/providers.dart';

import 'design_lab_mocks.dart';
import '../support/fake_bridge_service.dart';

const _visualQaEnvFlag = 'TODORI_VISUAL_QA';

bool get _visualQaEnabled => Platform.environment[_visualQaEnvFlag] == '1';

const _outputDir = 'build/visual_qa';
const _mobileLogicalSize = Size(390, 844);
const _mobileDevicePixelRatio = 3.0;

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

  testWidgets('home_tasks: root with a realistic mixed task list', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await _screenshot(tester, 'home_tasks');
  });

  testWidgets(
    'home_tasks_ja: root with a realistic mixed task list, ja locale',
    (tester) async {
      _setMobileViewport(tester);
      _useJaLocale(tester);
      await _seedRealisticData(tester);
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
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await _screenshot(tester, 'home_tasks_empty');
  });

  testWidgets('wont_do_row: closed section with a wont_do row', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    await fake.createTask(listId: listId, title: 'Review launch brief');
    final skipped = await fake.createTask(
      listId: listId,
      title: 'Replace the planning spreadsheet',
    );
    await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');
    final done = await fake.createTask(
      listId: listId,
      title: 'Send weekly notes',
    );
    await fake.setTaskStatus(taskId: done.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('completed-section-toggle')));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'wont_do_row');
  });

  testWidgets('lists: list management screen with two lists', (tester) async {
    _setMobileViewport(tester);
    await _seedArchivedListData(tester);
    await tester.tap(find.byTooltip('Open lists'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists');
  });

  testWidgets('lists_archived: archived section expanded', (tester) async {
    _setMobileViewport(tester);
    await _seedArchivedListData(tester);
    await tester.tap(find.byTooltip('Open lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show archived lists'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists_archived');
  });

  testWidgets('list_actions_menu: opened list overflow menu', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final work = await fake.createList(name: '仕事', sortOrder: 'a1');
    await fake.createTask(listId: work.id, title: '四半期レビュー資料を作成する');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仕事'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('List actions'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'list_actions_menu');
  });

  testWidgets('task_detail: parent task with three subtasks', (tester) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await _screenshot(tester, 'task_detail');
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
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final work = await fake.createList(name: 'Work', sortOrder: 'a1');
    await fake.createTask(listId: work.id, title: 'Completed planning note');
    final done = await fake.createTask(listId: work.id, title: 'Done task');
    await fake.setTaskStatus(taskId: done.id, status: 'done');

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open lists'));
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
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;
    final parent = await fake.createTask(
      listId: listId,
      title: 'Ship the release notes',
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

  testWidgets('design_lab_task_list: focus timer task list exploration', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskList),
    );
    await _screenshot(tester, 'design_lab_task_list');
  });

  testWidgets('design_lab_list_overview: smart and custom lists exploration', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.listOverview),
    );
    await _screenshot(tester, 'design_lab_list_overview');
  });

  testWidgets('design_lab_focus_timer: focus timer screen exploration', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.focusTimer),
    );
    await _screenshot(tester, 'design_lab_focus_timer');
  });

  testWidgets('design_lab_task_detail: task detail exploration', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskDetail),
    );
    await _screenshot(tester, 'design_lab_task_detail');
  });

  testWidgets('design_lab_task_create_sheet: task create sheet exploration', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.taskCreateSheet),
    );
    await _screenshot(tester, 'design_lab_task_create_sheet');
  });

  testWidgets('design_lab_search: search exploration', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(const DesignLabMockApp(mock: DesignLabMock.search));
    await _screenshot(tester, 'design_lab_search');
  });

  testWidgets('design_lab_settings: settings exploration', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.settings),
    );
    await _screenshot(tester, 'design_lab_settings');
  });

  testWidgets('design_lab_timer_setup: timer setup exploration', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      const DesignLabMockApp(mock: DesignLabMock.timerSetup),
    );
    await _screenshot(tester, 'design_lab_timer_setup');
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
  const _SeedData({required this.fake, required this.parentWithSubtasksTitle});

  final FakeBridgeService fake;
  final String parentWithSubtasksTitle;
}

/// Seeds two lists ("Inbox" as the home list, "仕事" as a second list) with a
/// realistic, mixed set of tasks and pumps [TodoriApp] on top of them:
///
/// - priorities: high, medium, low, and none all appear.
/// - due dates: today, tomorrow, overdue, and no-due-date all appear.
/// - one task is already completed and one is closed as wont_do.
/// - one task ("Plan the product launch event") has three subtasks, one of
///   which is completed.
/// - titles mix Japanese and English, and one title is long enough to wrap.
Future<_SeedData> _seedRealisticData(WidgetTester tester) async {
  final fake = FakeBridgeService();
  await fake.createList(name: 'Inbox', sortOrder: 'a0');
  await fake.createList(name: '仕事', sortOrder: 'a1');
  final lists = await fake.getLists();
  final homeListId = lists[0].id;
  final workListId = lists[1].id;

  DateTime atMidnight(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  final now = DateTime.now();
  final today = atMidnight(now).millisecondsSinceEpoch;
  final tomorrow = atMidnight(
    now.add(const Duration(days: 1)),
  ).millisecondsSinceEpoch;
  final overdue = atMidnight(
    now.subtract(const Duration(days: 4)),
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
    dueAt: today,
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
    dueAt: today,
  );
  final checklist = await fake.createTask(
    listId: homeListId,
    title: 'Draft the launch checklist',
    parentTaskId: launch.id,
  );
  await fake.setTaskStatus(taskId: checklist.id, status: 'done');
  await fake.createTask(
    listId: homeListId,
    title: 'Review checklist with design',
    parentTaskId: launch.id,
  );
  await fake.createTask(
    listId: homeListId,
    title: 'Confirm final copy in the hero panel',
    parentTaskId: checklist.id,
  );
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
    dueAt: tomorrow,
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
    dueAt: null,
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
    dueAt: overdue,
  );

  final standup = await fake.createTask(listId: homeListId, title: '朝会に参加する');
  await fake.setTaskStatus(taskId: standup.id, status: 'done');

  final skipped = await fake.createTask(
    listId: homeListId,
    title: 'Replace the planning spreadsheet',
  );
  await fake.setTaskStatus(taskId: skipped.id, status: 'wont_do');

  await fake.createTask(listId: workListId, title: '四半期レビュー資料を作成する');

  await tester.pumpWidget(
    TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
  );
  await tester.pumpAndSettle();

  return _SeedData(
    fake: fake,
    parentWithSubtasksTitle: parentWithSubtasksTitle,
  );
}

Future<void> _seedArchivedListData(WidgetTester tester) async {
  final fake = FakeBridgeService();
  await fake.createList(name: 'Inbox', sortOrder: 'a0');
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
  final finder = find.text(title);
  await tester.scrollUntilVisible(finder, 200);
  await tester.pumpAndSettle();
  await tester.tap(finder);
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
