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
  String get defaultInboxName => 'インボックス';

  @override
  String get defaultListMissing =>
      '既定リストが見つかりません。Todoriを再起動するか、ローカルDBの初期化状態を確認してください。';

  @override
  String get listsTitle => 'リスト';

  @override
  String get listsSectionTitle => 'リスト';

  @override
  String get listsEmpty => 'リストがありません。+をタップして作成してください。';

  @override
  String get listsEmptyTitle => 'リストがありません。';

  @override
  String get listsEmptyBody => '+をタップして作成してください。';

  @override
  String failedToLoadLists(String error) {
    return 'リストの読み込みに失敗しました: $error';
  }

  @override
  String get newListTooltip => '新しいリスト';

  @override
  String get newListTitle => '新しいリスト';

  @override
  String get listActionsTooltip => 'リスト操作';

  @override
  String get listsMoreMenuTooltip => 'その他';

  @override
  String get renameListMenuItem => '名称変更';

  @override
  String get renameListTitle => 'リスト名を変更';

  @override
  String get archiveListMenuItem => 'アーカイブ';

  @override
  String get deleteListMenuItem => '削除';

  @override
  String get unarchiveListMenuItem => 'アーカイブ解除';

  @override
  String deleteListDialogTitle(String listName) {
    return '「$listName」を削除しますか？';
  }

  @override
  String deleteListDialogMessage(int taskCount) {
    return 'このリストと配下のタスク $taskCount件（完了済みを含む）は完全に削除され、元に戻せません。履歴を残す場合は削除ではなくアーカイブしてください。';
  }

  @override
  String archivedListsSectionTitle(int count) {
    return 'アーカイブ済み（$count件）';
  }

  @override
  String get showArchivedListsTooltip => 'アーカイブ済みリストを表示';

  @override
  String get hideArchivedListsTooltip => 'アーカイブ済みリストを隠す';

  @override
  String get nameLabel => '名前';

  @override
  String get cancelButton => 'キャンセル';

  @override
  String get deleteButton => '削除';

  @override
  String get createButton => '作成';

  @override
  String get tasksTitle => 'タスク';

  @override
  String get homeTitle => 'ホーム';

  @override
  String get todayTitle => '今日';

  @override
  String get homeOverdueSectionTitle => '期限超過';

  @override
  String get homeTomorrowSectionTitle => '明日';

  @override
  String get homeUpcomingSectionTitle => '今後';

  @override
  String get homeTasksSectionTitle => 'タスク';

  @override
  String homePendingCount(int count) {
    return '未完了 $count件';
  }

  @override
  String get completedTasksTitle => 'クローズ済み';

  @override
  String get showCompletedTasksTooltip => 'クローズ済みタスクを表示';

  @override
  String get hideCompletedTasksTooltip => 'クローズ済みタスクを隠す';

  @override
  String get homeListMenuTooltip => 'リストを開く';

  @override
  String get homeSmartListTooltip => 'ホームを開く';

  @override
  String showHomeSectionTooltip(String section) {
    return '$sectionのタスクを表示';
  }

  @override
  String hideHomeSectionTooltip(String section) {
    return '$sectionのタスクを隠す';
  }

  @override
  String get homeEmptyTitle => 'まずリストを作成';

  @override
  String get homeEmptyBody => 'リストを作成すると、次回からすぐタスクに入れます。';

  @override
  String get homeNewListButton => '新しいリスト';

  @override
  String get addTaskButton => 'タスクを追加';

  @override
  String get quickAddHint => 'タスクを追加';

  @override
  String get quickAddOpenTooltip => 'タスク作成を開く';

  @override
  String get quickAddOpenSemantics => 'タスク作成シートを開く';

  @override
  String get quickAddSubmitTooltip => 'タスクを追加';

  @override
  String get quickAddTextFieldSemantics => 'クイック追加するタスクのタイトル';

  @override
  String get quickAddCreateError => 'タスクを追加できませんでした。';

  @override
  String get taskCreateTitleHint => 'タスクを追加...';

  @override
  String get taskCreateListChip => 'リスト';

  @override
  String get taskCreateListTooltip => 'リストを選択';

  @override
  String get taskCreateDueChip => '期限';

  @override
  String get taskCreateDueTooltip => '期限日を選択';

  @override
  String taskCreateDueChipSemantics(String dueAt) {
    return '期限日: $dueAt';
  }

  @override
  String get tasksEmpty => 'タスクがありません。+をタップして作成してください。';

  @override
  String get tasksEmptyTitle => 'タスクがありません。';

  @override
  String get tasksEmptyBody => '+をタップして作成してください。';

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
  String get noteLabel => 'ノート';

  @override
  String get taskDetailTitle => 'タスク詳細';

  @override
  String failedToLoadTask(String error) {
    return 'タスクの読み込みに失敗しました: $error';
  }

  @override
  String get taskNotFound => 'タスクが見つかりません。';

  @override
  String taskPriority(String priority) {
    return '優先度: $priority';
  }

  @override
  String taskDueAt(String dueAt) {
    return '$dueAt';
  }

  @override
  String taskRowStatusSemantics(String status) {
    return '状態: $status';
  }

  @override
  String taskRowDueSemantics(String dueAt) {
    return '期限: $dueAt';
  }

  @override
  String taskRowListSemantics(String listName) {
    return 'リスト: $listName';
  }

  @override
  String taskRowSubtaskLevelSemantics(int level) {
    return 'サブタスク階層 $level';
  }

  @override
  String get taskRowOpenHint => 'ダブルタップでタスクを開く';

  @override
  String get dueToday => '今日';

  @override
  String get dueTomorrow => '明日';

  @override
  String taskDueOverdue(String dueAt) {
    return '期限超過: $dueAt';
  }

  @override
  String taskCreatedAt(String createdAt) {
    return '作成日時: $createdAt';
  }

  @override
  String get addNotePlaceholder => 'ノートを追加';

  @override
  String get editTaskTitleSemantics => 'タスクのタイトルを編集';

  @override
  String get editTaskNoteSemantics => 'タスクのノートを編集';

  @override
  String parentTaskLinkTooltip(String title) {
    return '親タスクを開く: $title';
  }

  @override
  String parentTaskLinkSemantics(String title) {
    return '親タスク: $title';
  }

  @override
  String get changeDueDateTooltip => '期限日を変更';

  @override
  String get reminderChipEmpty => 'リマインダー';

  @override
  String get reminderChipTooltipSet => 'リマインダーを設定';

  @override
  String get reminderChipTooltipChange => 'リマインダーを変更';

  @override
  String get clearReminderButton => 'リマインダーを解除';

  @override
  String get reminderPermissionDenied =>
      '通知がオフです。リマインダーは保存しましたが、Todoriはローカル通知を登録できませんでした。';

  @override
  String failedToSaveReminder(String error) {
    return 'リマインダーの保存に失敗しました: $error';
  }

  @override
  String get reminderNotificationTitle => 'Todori リマインダー';

  @override
  String get reminderNotificationBody => 'タスクのリマインダー時刻です。';

  @override
  String get reminderSnoozeOneHourAction => '1時間後';

  @override
  String get changePriorityTooltip => '優先度を変更';

  @override
  String get subtasksTitle => 'サブタスク';

  @override
  String get subtasksEmpty => 'サブタスクはまだありません。';

  @override
  String get addSubtaskButton => 'サブタスクを追加';

  @override
  String get newSubtaskTitle => '新しいサブタスク';

  @override
  String subtaskProgress(int doneCount, int totalCount) {
    return '$doneCount/$totalCount';
  }

  @override
  String get completeTaskDialogTitle => '親タスクを完了しますか？';

  @override
  String get completeTaskDialogMessage =>
      'このタスクには未完了のサブタスクがあります。親タスクを完了しても、サブタスクは自動では完了しません。';

  @override
  String get wontDoTaskDialogTitle => '親タスクを対応しないとして閉じますか？';

  @override
  String get wontDoTaskDialogMessage =>
      'このタスクには未完了のサブタスクがあります。親タスクを対応しないとして閉じても、サブタスクは自動では閉じられません。';

  @override
  String get continueButton => '続行';

  @override
  String get statusTodo => '未着手';

  @override
  String get statusInProgress => '進行中';

  @override
  String get statusDone => '完了';

  @override
  String get statusWontDo => '対応しない';

  @override
  String get editTaskTooltip => 'タスクを編集';

  @override
  String get taskActionsTooltip => 'タスク操作';

  @override
  String get completeTaskTooltip => 'タスクを完了にする';

  @override
  String get markTaskDoneMenuItem => '完了にする';

  @override
  String get markTaskWontDoMenuItem => '対応しない';

  @override
  String get reopenTaskTooltip => 'タスクを再オープン';

  @override
  String get reopenTaskMenuItem => '再オープン';

  @override
  String get editTaskTitle => 'タスクを編集';

  @override
  String get priorityLabel => '優先度';

  @override
  String get priorityNone => 'なし';

  @override
  String get priorityLow => '低';

  @override
  String get priorityMedium => '中';

  @override
  String get priorityHigh => '高';

  @override
  String get dueDateLabel => '期限日';

  @override
  String get noDueDate => '期限なし';

  @override
  String get setDueDateButton => '日付を設定';

  @override
  String get clearDueDateButton => '日付をクリア';

  @override
  String get saveButton => '保存';

  @override
  String get titleRequiredError => 'タイトルは必須です。';

  @override
  String failedToSaveTask(String error) {
    return 'タスクの保存に失敗しました: $error';
  }

  @override
  String get deleteTaskMenuItem => '削除';

  @override
  String get deleteTaskDialogTitle => 'タスクを削除しますか？';

  @override
  String get deleteTaskDialogMessage => 'このタスクは完全に削除され、元に戻せません。';

  @override
  String deleteTaskDialogMessageWithDescendants(int descendantCount) {
    return 'このタスクと配下のサブタスク $descendantCount件は完全に削除され、元に戻せません。';
  }

  @override
  String get undoActionLabel => '元に戻す';

  @override
  String get undoCompleteMessage => 'タスクを完了しました。';

  @override
  String get undoCloseMessage => 'タスクを閉じました。';

  @override
  String get undoEditMessage => 'タスクを保存しました。';

  @override
  String get undoSuccessMessage => '元に戻しました。';

  @override
  String undoFailedMessage(String error) {
    return '元に戻せませんでした: $error';
  }

  @override
  String get taskSortTooltip => 'タスクの表示順';

  @override
  String get taskSortManual => '手動順';

  @override
  String get taskSortDueDate => '締切順';

  @override
  String get taskSortPriority => '優先度順';

  @override
  String get taskSortCreatedAt => '作成順';

  @override
  String get moveTaskUpTooltip => 'タスクを上へ移動';

  @override
  String get moveTaskDownTooltip => 'タスクを下へ移動';

  @override
  String get accountTitle => 'アカウント';

  @override
  String get accountLoadFailed => 'アカウント状態を読み込めませんでした。';

  @override
  String get accountLoginTab => 'ログイン';

  @override
  String get accountRegisterTab => '登録';

  @override
  String get accountEmailLabel => 'メール';

  @override
  String get accountPasswordLabel => 'パスワード';

  @override
  String get accountLoginButton => 'ログイン';

  @override
  String get accountRegisterButton => '登録';

  @override
  String get accountLogoutButton => 'ログアウト';

  @override
  String get accountServerUrlLabel => 'サーバーURL';

  @override
  String get accountSaveServerUrlTooltip => 'サーバーURLを保存';

  @override
  String get accountRequestFailed => 'アカウント処理に失敗しました。';

  @override
  String failedToStartTodori(String error) {
    return 'Todoriの起動に失敗しました: $error';
  }
}
