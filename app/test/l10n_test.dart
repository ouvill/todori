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
    expect(en.listsTitle, isNot(ja.listsTitle));
    expect(en.tasksTitle, isNot(ja.tasksTitle));
  });
}
