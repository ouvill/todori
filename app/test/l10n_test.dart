import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todori/src/generated/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads English and Japanese localizations', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(en.appTitle, 'Todori');
    expect(ja.appTitle, 'Todori');
    expect(en.listsTitle, 'Lists');
    expect(ja.listsTitle, 'リスト');
    expect(en.tasksTitle, 'Tasks');
    expect(ja.tasksTitle, 'タスク');
    expect(en.createButton, 'Create');
    expect(ja.createButton, '作成');
    expect(en.cancelButton, 'Cancel');
    expect(ja.cancelButton, 'キャンセル');
    expect(en.dueToday, 'Today');
    expect(ja.dueToday, '今日');
    expect(en.taskSortTooltip, 'Sort tasks');
    expect(ja.taskSortTooltip, 'タスクの表示順');
    expect(en.taskSortDueDate, 'Due date');
    expect(ja.taskSortDueDate, '締切順');
    expect(en.listsTitle, isNot(ja.listsTitle));
    expect(en.tasksTitle, isNot(ja.tasksTitle));
  });
}
