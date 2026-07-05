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

  testWidgets('lists: list management screen with two lists', (tester) async {
    _setMobileViewport(tester);
    await _seedRealisticData(tester);
    await tester.tap(find.byTooltip('Open lists'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'lists');
  });

  testWidgets('task_detail: parent task with three subtasks', (tester) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await _screenshot(tester, 'task_detail');
  });

  testWidgets('task_edit_dialog: edit dialog open over task detail', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final seed = await _seedRealisticData(tester);
    await _openTask(tester, seed.parentWithSubtasksTitle);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'task_edit_dialog');
  });

  testWidgets('trash: two deleted tasks', (tester) async {
    _setMobileViewport(tester);
    final fake = FakeBridgeService();
    await fake.createList(name: 'Inbox', sortOrder: 'a0');
    final listId = (await fake.getLists()).first.id;

    final meetingNotes = await fake.createTask(
      listId: listId,
      title: 'Cancelled kickoff meeting notes',
    );
    final oldDraft = await fake.createTask(
      listId: listId,
      title: '古い下書きのタスクを削除する',
    );
    await fake.updateTask(
      taskId: oldDraft.id,
      title: oldDraft.title,
      note: '',
      priority: 2,
      dueAt: DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch,
    );
    await fake.trashTask(taskId: meetingNotes.id);
    await fake.trashTask(taskId: oldDraft.id);

    await tester.pumpWidget(
      TodoriApp(overrides: [bridgeServiceProvider.overrideWithValue(fake)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open trash'));
    await tester.pumpAndSettle();
    await _screenshot(tester, 'trash');
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
}

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
/// - one task is already completed.
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
    title: 'デザインレビューのフィードバックを反映する',
    parentTaskId: launch.id,
  );

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
/// - The bundled brand typefaces (`assets/fonts/Lora`, `assets/fonts/Inter`;
///   see `app/pubspec.yaml` `fonts:` and `docs/design/visual-direction.md`)
///   are registered under their real family names, each weight in turn, so
///   the "Today"/screen-title serif (Lora) and UI body sans (Inter) render
///   as designed instead of falling back to the test harness's tofu boxes.
/// - A macOS system font that can render Japanese glyphs is registered under
///   the `Hiragino Sans` family -- the same name `theme.dart` declares in
///   `fontFamilyFallback` -- so mixed Japanese/English seed data resolves
///   Japanese glyphs through that *separate* family instead of tofu.
///
///   (Registering the Japanese font as extra same-family candidates on
///   'Inter'/'Lora' directly, as `FontLoader`'s docs suggest is possible,
///   was tried first and did not work here: once a family has multiple
///   candidates of different declared weights, Skia's style matching picks
///   the closest-weight *Latin* candidate for a run and does not appear to
///   retry sibling candidates in that family for glyphs it lacks. Routing
///   Japanese through `fontFamilyFallback` -- a separate, single-typeface
///   family that Flutter tries per missing glyph -- is what actually
///   renders Japanese here.)
Future<void> _loadRealFonts() async {
  await _loadMaterialIconsFont();
  await _loadBrandFont(family: 'Inter', weightPaths: _interWeightPaths);
  await _loadBrandFont(family: 'Lora', weightPaths: _loraWeightPaths);
  await _loadBrandFont(
    family: 'Newsreader',
    weightPaths: _newsreaderWeightPaths,
  );
  await _loadCjkFallbackFont();
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
