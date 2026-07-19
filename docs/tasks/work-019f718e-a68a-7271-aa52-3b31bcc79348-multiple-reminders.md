---
id: 019f718e-a68a-7271-aa52-3b31bcc79348
title: Multiple local reminders
status: done
lane: standard
milestone: maintenance
---

# Multiple local reminders

## 1. 背景とコンテキスト

F-25と技術仕様は1タスクに複数の通知時刻を許容するが、現行の設定APIは既存行を削除して1件へ置換し、タスク詳細UIも先頭1件だけを扱う。また、置換時に以前のOS通知が残る可能性がある。本work itemで、既存の複数行対応schemaを利用し、端末ローカル通知として複数リマインダーを完成させる。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/02_機能仕様書.md` F-24〜F-26
- `docs/03_技術仕様書.md` §3.7、§4.10
- `docs/tasks/task-65-local-notifications.md`
- `core/storage/src/lib.rs`
- `core/client/src/runtime/application.rs`
- `app/rust/src/api.rs`
- `app/lib/src/notifications/reminder_notifications.dart`
- `app/lib/src/screens/task_detail_screen.dart`

## 3. ゴール

1タスクに最大5件のリマインダーを追加、編集、個別削除でき、各レコードとOS通知がID単位で一致すること。日時付き締切から5分前、30分前、1時間前、1日前を登録時に逆算できること。

## 4. スコープ

### やること

- 置換APIを作成、更新、個別削除APIへ分割する。
- 未来時刻、重複禁止、最大5件をcoreで検証する。
- タスク詳細に複数件の管理シートと締切基準の候補を追加する。
- OS通知の個別登録、更新、取消と起動時照合を実装する。
- 完了時の全取消、再オープン時の未来分再登録、閉鎖済みtaskのsnooze拒否を実装する。
- en/ja l10n、Rust、Dart、widget test、visual QAを更新する。

### やらないこと

- DB schema migration。
- reminderの端末間同期、sync protocol、暗号設計の変更。
- 締切変更へ追従する相対offsetの永続化。
- `task-65`の履歴変更。

## 5. 実装手順

1. storage/client/FRB APIをcreate/update/deleteへ分割し、不変条件を追加する。
2. Dart bridge/providerと通知gatewayへ個別操作とpending照合を追加する。
3. タスク詳細の管理シート、候補、日時選択、個別操作を実装する。
4. Rust、Dart、widget testとvisual QAを更新し、FRB/l10nを再生成する。
5. 全品質ゲートと独立検証を実行する。

## 6. 受け入れ基準

- [x] 1タスクに異なる時刻のリマインダーを最大5件保存できる。
- [x] 過去時刻、重複時刻、6件目をcoreが拒否する。
- [x] 編集はreminder IDを維持してsnoozeを解除し、個別削除は他のreminderへ影響しない。
- [x] タスク詳細で0件、1件、複数件の要約と管理シートが英日表示される。
- [x] 日時付き締切で5分前、30分前、1時間前、1日前を選べる。
- [x] 追加、編集、削除、snooze、完了、再オープン、削除がOS通知へ正しく反映される。
- [x] 起動時照合が孤児reminder通知を削除し、timer等の別通知を変更しない。
- [x] `docs/tasks/README.md`の該当品質ゲートと独立検証が合格する。

## 7. 制約・注意事項

- reminderはSQLCipher DBとOSローカル通知だけで扱う。
- payload、log、完了報告へtask本文、鍵、tenant/device識別子を含めない。
- FRB生成物とl10n生成物は手編集しない。
- 元の`taskveil/` worktreeを変更しない。

## 8. 完了報告に含めるべき内容

- API、UI、通知照合、validationの実装結果。
- 追加・更新したテストとvisual QA。
- 実行した品質ゲート、独立検証、環境制約。
- commitと未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-18
- 結果: 既存schemaを変更せず、reminder APIを作成・更新・個別削除へ分割し、未来時刻、同一task内の重複禁止、最大5件、閉鎖task拒否をstorageで保証した。task詳細は0件・1件・複数件の要約から管理sheetを開き、実効通知時刻順の過去を含む一覧、個別編集・削除、任意日時、日時付き期限からの4候補を扱う。OS通知はreminder IDごとの登録・更新・取消、完了・`wont_do`・削除時の取消、明示的再openと完了Undo後の再登録、閉鎖・削除済みsnooze拒否に対応した。起動時はowner付きpayloadとcanonical通知IDでDBと照合し、legacy payloadはcanonical IDの場合だけ移行対象とするため、timerと未認識通知には触れない。
- 証拠: storageの複数共存・並び順・更新・削除・重複・5件上限test、Dartの3通知ID・個別更新/削除/snooze・権限拒否・孤児/非canonical取消・閉鎖/再open/Undo test、widgetの複数件管理sheetと期限候補testを追加した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、Rust release build、`flutter analyze`、Flutter全273 test、hardcoded string/client boundary checks、`git diff --check`が成功した。FRBとl10nを再生成し、`sh app/tool/visual_qa.sh`で131 screenshotを生成、`task_detail_reminders_sheet`で2件の時刻順一覧と個別操作を目視確認した。full Cargo testはsandbox内のlocal socket bind制限だけで一度失敗し、同一commandをsandbox外で再実行して成功した。
- Commit: この完了報告を含むcommit
- 未解決: なし。push、PR作成、worktree削除は実施していない。

### 独立検証

- 判定: 合格
- 根拠: 初回検証で完了Undo時の通知再登録漏れとpayload所有権/canonical ID照合不足を指摘された。完了Undo再登録、owner discriminator、legacy互換のcanonical ID限定、非canonical通知取消と回帰testを追加後、Rust reminder 4 test、bridge 3 test、Flutter reminder + widget 106 test、Flutter analyze、Rust fmt/clippy、hardcoded string/client boundary checks、`git diff --check`を再実行し、残存するblocking/medium findingなしと判定された。
- 検証者: 実装を担当していない独立検証エージェント `/root/independent_verification`
