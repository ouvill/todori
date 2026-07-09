# task-80 同期pull取りこぼし回復とUI更新漏れ修正

> ステータス: 完了（2026-07-10）
> 作業日: 2026-07-10

## 1. 背景

2026-07-10の実機同期確認で、同期pull適用後にリスト内タスク一覧が更新されないUI更新漏れと、旧バイナリ時代にDEK未取得で復号スキップ後にpullカーソルだけ前進した端末の回復手段不足が見つかった。

## 2. ゴール

- `SyncStatusNotifier.syncNow()` 後に同期で変わり得るDart providerを無効化する。
- login/register成功時に初回backfillカーソルだけでなくpullカーソルも削除し、次回同期を `since=0` から再pullさせる。
- ADR-010のフル再同期実装までの既知回復策としてBACKLOGへ記録する。

## 9. 完了報告

### 作業日

2026-07-10

### 変更ファイル

- `app/lib/src/core/providers.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/sync_provider_test.dart`
- `app/rust/src/support.rs`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/README.md`
- `docs/tasks/task-80-sync-pull-recovery.md`

### 実装結果

- `SyncStatusNotifier.syncNow()` 後のinvalidate対象に `tasksProvider` / `latestTaskUndoProvider` / `taskRemindersProvider` を追加した。
- `taskDetailProvider` は `tasksProvider` 派生のため、`tasksProvider` family全体のinvalidateで更新される。
- `taskSortModeProvider` はUI状態のみのため対象外とした。
- login/register成功時のカーソルリセットを `reset_login_sync_cursors()` に集約し、`INITIAL_BACKFILL_CURSOR_NAME` と `todori_sync::SYNC_CURSOR_NAME` の両方を削除するようにした。
- `FakeBridgeService.addRemoteTaskForNextSync()` と `sync_provider_test.dart` のテストで、`syncNow()` 後に `tasksProvider(listId)` が再構築されることを確認するケースを追加した。
- BACKLOG #19へ、DEK未取得時の復号スキップ後にpullカーソルが前進して取りこぼす実機確認事象と、task-80での暫定回復策を追記した。

### invalidate対象の最終一覧

- `listsProvider`
- `archivedListsProvider`
- `tasksProvider`
- `homeTasksProvider`
- `latestTaskUndoProvider`
- `taskRemindersProvider`

### 検証結果

- `cd app && flutter analyze`: 成功（No issues found）
- `cd app && flutter test`: 成功（124件成功、1件skip）
- `cargo build -p todori_app_bridge`: 成功
- `cargo clippy -p todori_app_bridge -- -D warnings`: 成功
- `cargo fmt --all -- --check`: 成功
- `sh app/tool/check_hardcoded_strings.sh`: 成功

### 未解決事項

- ADR-010のフル再同期とGCホライズン実装はBACKLOG #19で継続する。
