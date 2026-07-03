// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Todori';

  @override
  String get listsTitle => 'リスト';

  @override
  String get listsEmpty => 'リストがありません。+をタップして作成してください。';

  @override
  String failedToLoadLists(String error) {
    return 'リストの読み込みに失敗しました: $error';
  }

  @override
  String get newListTooltip => '新しいリスト';

  @override
  String get newListTitle => '新しいリスト';

  @override
  String get nameLabel => '名前';

  @override
  String get cancelButton => 'キャンセル';

  @override
  String get createButton => '作成';

  @override
  String get tasksTitle => 'タスク';

  @override
  String get tasksEmpty => 'タスクがありません。+をタップして作成してください。';

  @override
  String failedToLoadTasks(String error) {
    return 'タスクの読み込みに失敗しました: $error';
  }

  @override
  String get newTaskTooltip => '新しいタスク';

  @override
  String get newTaskTitle => '新しいタスク';

  @override
  String get titleLabel => 'タイトル';

  @override
  String get taskDetailTitle => 'タスク詳細';

  @override
  String failedToLoadTask(String error) {
    return 'タスクの読み込みに失敗しました: $error';
  }

  @override
  String get taskNotFound => 'タスクが見つかりません。';

  @override
  String taskStatus(String status) {
    return 'ステータス: $status';
  }

  @override
  String taskPriority(int priority) {
    return '優先度: $priority';
  }

  @override
  String taskCreatedAt(int createdAt) {
    return '作成日時: $createdAt';
  }

  @override
  String get moveToTrashButton => 'ゴミ箱へ移動';

  @override
  String failedToStartTodori(String error) {
    return 'Todoriの起動に失敗しました: $error';
  }
}
