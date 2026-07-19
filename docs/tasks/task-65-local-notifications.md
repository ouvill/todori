# task-65: ローカル通知（M4-01 / F-24・F-25）

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

TaskveilはE2EE Todoアプリであり、リマインダー日時もタスク内容と同じくサーバーから不可視である。`docs/02_機能仕様書.md` F-24は通知を端末内ローカル通知に限定し、`docs/03_技術仕様書.md` §4.10もサーバー起点push通知を採らない制約を明記している。Phase 1計画書のM4-01は、iOSローカル通知とスヌーズ最小版を実装し、通知登録、通知取消、スヌーズ再登録をiOS実機/Simulatorで確認することを完了条件にしている。

本タスクでは `flutter_local_notifications` を採用する。人間の包括承認済みのため、`app/pubspec.yaml` への依存追加を行ってよい。Phase 1ではiOSを先行対象とし、macOSはdogfooding確認対象、Androidは後続検証対象として扱う。

`docs/03_技術仕様書.md` §3.7には `reminders` テーブル定義があるが、現行 `core/storage` はv5（`settings`）までで `reminders` は未実装である。必要ならv6マイグレーションとして仕様どおり追加し、storage/domain/bridge/Dart/UI/通知スケジューラまで縦貫通させる。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/02_機能仕様書.md` F-24〜F-26
- `docs/03_技術仕様書.md` §3.7、§4.10、§5のローカルDB関連節
- `docs/07_Phase1計画書.md` §1の通知方針、§4 M4-01、§5のローカル通知リスク
- `docs/design/ui-spec.md` のチップ/pill、Task detail、Lucideアイコン規則
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `app/lib/main.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/router.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`

## 3. ゴール

- `flutter_local_notifications` を導入し、iOS/macOS向けのローカル通知初期化、権限リクエスト、スケジュール、キャンセル、通知アクションを実装する。
- `reminders` テーブルをv6マイグレーションで追加し、1タスクに複数リマインダーを保存できるstorage APIを用意する。
- Phase 1 UIでは、タスク詳細のチップ列に「リマインダー」チップを追加し、日時選択、設定、変更、解除ができるようにする。
- 初回リマインダー設定時に通知権限をリクエストし、拒否時は静かな案内文言を表示する。
- 通知タップでアプリを起動できるようにする。該当タスク詳細への遷移は可能なら実装し、困難ならHome起動でよいが、判断理由を完了報告に記録する。
- F-25の最小版として、通知アクションから「+1時間」等のスヌーズ1種を実装し、同じreminderを再スケジュールする。
- アプリ起動時に未発火リマインダーを再スケジュールし、完了/削除されたタスクの通知をキャンセルする。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/pubspec.yaml`
- `app/pubspec.lock`
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/notifications/` 配下（新設可）
- `app/lib/main.dart`
- `app/lib/src/router.dart`（通知タップ遷移を実装する場合）
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下（生成物のみ）
- `app/test/support/fake_bridge_service.dart`
- `app/test/` 配下の関連テスト
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-65-local-notifications.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `flutter_local_notifications` を `app/pubspec.yaml` に追加する。追加は人間の包括承認済みである。
2. `core/storage` の `LATEST_SCHEMA_VERSION` を6へ上げ、v6 migrationで `reminders` を追加する。定義は `docs/03_技術仕様書.md` §3.7に従い、`id`、`task_id`、`remind_at`、`snoozed_until`、`created_at` を持たせる。
3. `schema.sql` の新規DB作成経路にも `reminders` を含める。v1 baseline validationとmigrationテストに影響する場合は、既存方針を崩さず必要最小限で調整する。
4. storage層へリマインダー操作APIを追加する。最低限、タスク単位の設定、解除、一覧取得、未発火一覧取得、スヌーズ更新、完了/削除時キャンセルに必要な取得ができること。
5. `app/rust/src/api.rs` へリマインダーAPIを公開し、Rust API変更後は `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行する。生成物は手編集しない。
6. Dart側の `BridgeService` / `FrbBridgeService` / `FakeBridgeService` とRiverpod providerへリマインダーAPIを追加する。`AsyncNotifier` + `invalidateSelf` の既存方針に合わせる。
7. `flutter_local_notifications` を薄いサービス層で包み、テストでは権限・初期化・スケジュール・キャンセル・アクション応答をモック化できるようにする。
8. アプリ起動時に通知サービスを初期化し、未発火リマインダーを再スケジュールする。DB初期化より前に通知処理がDBへ触れないよう、`main.dart` の初期化順序を明確にする。
9. タスク詳細の `_EditableTaskMetadata` 周辺へリマインダーチップを追加する。未設定時は「リマインダー」、設定済みなら時刻表示にし、タップで日時選択、変更、解除ができるようにする。チップ文法とLucideアイコン規則に従う。
10. 初回設定時に通知権限をリクエストする。拒否された場合は、タスク詳細上または軽いSnackBar/ダイアログで静かな案内文言を表示し、タスク保存自体を壊さない。
11. 通知スケジュールはiOS/macOS対応を優先する。Androidはコンパイルを壊さない範囲で後続検証扱いにし、完了報告へ残す。
12. 通知タップでアプリを起動する。payloadにはタスクID/リストID/リマインダーIDなど、秘密情報ではないIDのみを入れる。該当タスク詳細へ遷移できるなら実装し、難しい場合はHome起動に留めて判断を記録する。
13. スヌーズ最小版として通知アクションを1つ追加する。ラベルは「+1 hour」/「1時間後」相当とし、選択時に `snoozed_until` を更新して再スケジュールする。
14. タスクが `done` / `wont_do` になったとき、または物理削除されたときは、該当タスクの未発火通知をキャンセルする。親削除で子孫も削除される場合は子孫リマインダーも漏れなく扱う。
15. en/ja ARBへUI文字列を追加し、`flutter gen-l10n` を実行する。UI文字列の直書きは禁止。
16. visual QAにリマインダーチップ付き詳細画面のスクリーンショットを追加または既存 `task_detail` seedを更新し、生成パスを完了報告へ記録する。

### やらないこと

- サーバーpush通知、APNs、FCM、通知時刻のサーバー同期。
- Android実通知の受け入れ確認。コンパイル可能性の維持に留め、実機検証は後続へ送る。
- F-25の完全な複数通知UI。storage/APIは複数reminderを許容するが、Phase 1 UIは最小の1件設定でよい。
- 繰り返し通知、自然言語日付入力、カレンダー連携。
- F-26のWindows/Linuxデスクトップ通知本実装。macOS dogfooding確認に留める。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。
- 通知payload、ログ、Debug出力へタスクタイトル、ノート、リマインダー時刻以外の不要な内容、Device Key、導出鍵などの秘密情報を含めること。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `flutter_local_notifications` の最新導入手順を公式ドキュメントで確認し、iOS/macOS初期化と通知アクションの最小構成を決める。
3. v6 `reminders` migrationと新規DB用 `schema.sql` を更新し、storageテストでv5→v6昇格、insert/list/delete/snooze、タスク削除時の扱いを確認する。
4. storage APIの型を決め、bridge DTOへ写す。日時は既存の `due_at` と同じくepoch millisecondsの `i64` / Dart `int` に揃える。
5. `app/rust/src/api.rs` に `set_task_reminder` / `clear_task_reminders` / `get_task_reminders` / `list_pending_reminders` / `snooze_reminder` 相当を公開する。命名は既存APIと整合させる。
6. FRB再生成を実行し、Dart bridge/fake/providerへ配線する。
7. `NotificationService` 相当を新設し、plugin直接呼び出しを画面から隠す。provider overrideでFakeに差し替えられる構成にする。
8. `main.dart` でRust core初期化後に通知初期化と未発火リマインダー再スケジュールを呼ぶ。初期化失敗時はアプリ全体を落とさず、通知だけ無効扱いにするかを実装内で判断し完了報告に記録する。
9. タスク詳細のチップ列へ `LucideIcons.bell300` などのLucideアイコンを使ったリマインダーチップを追加する。日時選択は既存の期日選択UIに近い文法を使い、時刻選択も入れる。
10. 権限拒否、設定成功、変更、解除、完了/削除キャンセル、起動時再スケジュール、スヌーズアクションをFlutterテストで確認する。
11. `sh app/tool/visual_qa.sh` でリマインダーチップ付き詳細画面を生成する。
12. iOS Simulator手動確認手順を完了報告に記録する。サンドボックスで実通知確認できない場合は環境起因として記録し、親ホスト確認待ちにする。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `flutter_local_notifications` が導入され、iOS/macOS向け初期化、権限リクエスト、通知アクション、通知タップ起動がpluginサービス層経由で呼ばれている。
- [ ] v6 migrationで `reminders` テーブルが追加され、新規DBとv5既存DBの両方で利用可能であることをRustテストで確認している。
- [ ] storage/bridge/Dart providerからタスクのリマインダー設定、解除、一覧取得、未発火一覧取得、スヌーズ更新ができ、FRB生成物が更新されている。
- [ ] タスク詳細のチップ列にLucide準拠のリマインダーチップが追加され、未設定、設定済み時刻表示、変更、解除、権限拒否案内がen/ja l10n込みで動く。
- [ ] アプリ起動時に未発火リマインダーを再スケジュールし、完了/`wont_do`/削除されたタスクの未発火通知をキャンセルしている。
- [ ] 通知アクションのスヌーズ1種（例: +1時間）が `snoozed_until` 更新と再スケジュールを行う。
- [ ] 通知payloadやログにタスクタイトル、ノート、鍵素材などの秘密情報を含めず、payloadはID等の最小情報に留めている。
- [ ] Flutter側の権限・plugin呼び出し・スケジュール・キャンセル・スヌーズはFake/Mockでテストされ、実通知の発火確認はiOS Simulator手動確認手順として完了報告に記録されている。
- [ ] リマインダーチップ付き詳細画面のvisual QAスクリーンショットを生成し、パスを完了報告に記録している。
- [ ] 通知タップ後の遷移方針（該当タスク詳細またはHome起動）と、その判断理由を完了報告に記録している。

## 7. 制約・注意事項

- E2EE設計上、サーバーpush通知は採用しない。通知時刻は端末内DBとOSローカル通知スケジューラだけで扱う。
- `reminders.remind_at` / `snoozed_until` はepoch millisecondsで統一する。タイムゾーン表示はDart側でローカル時刻へ整形する。
- `reminders` は1タスク複数件を許容する。ただしPhase 1 UIは1件設定でもよい。将来の複数時刻UIを妨げないstorage/APIにする。
- OS通知IDは安定して再計算できるか、DBに保存したIDと対応づける。アプリ再起動後のキャンセル/再スケジュールで同一通知を特定できること。
- iOS/macOSの権限状態や通知カテゴリ登録はpluginの制約に従う。権限拒否はエラー扱いで画面を壊さず、静かな案内に留める。
- `flutter_local_notifications` の初期化やcallbackから直接Rust bridgeを呼ぶ場合は、Rust core初期化完了後であることを保証する。保証できない場合は起動後にprovider/service層で処理する。
- タスク詳細チップは `docs/design/ui-spec.md` のpill文法に従う。新規Material Iconsは追加せず、Lucideを使う。
- UI文字列はすべて `app/lib/l10n/app_en.arb` / `app_ja.arb` に追加し、`flutter gen-l10n` を実行する。
- Rust APIを変更したらFRB再生成必須。生成物は手編集しない。
- `docs/03_技術仕様書.md` はこのタスクでは原則変更しない。実装中に仕様と矛盾する事実を見つけた場合は完了報告の未解決事項に記録する。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- 採用した `flutter_local_notifications` の設定、iOS/macOS初期化、通知カテゴリ/アクション、権限リクエスト方針
- v6 `reminders` スキーマ、migration内容、新規DB経路の更新内容
- storage/bridge/Dart provider/APIの追加内容とFRB再生成コマンド
- 通知ID/payload設計と、payload/logへ含めない情報
- タスク詳細リマインダーチップのUI挙動、権限拒否時の表示、en/ja l10nキー
- 起動時再スケジュール、完了/`wont_do`/削除時キャンセル、スヌーズ再スケジュールの実装内容
- 通知タップ時の遷移方針と判断理由
- 追加・更新したRust/Flutterテスト名と検証対象
- visual QAスクリーンショットのパス
- iOS Simulator手動確認の機種、OS、device id、手順、結果（実通知の発火、取消、スヌーズ再登録）
- macOS dogfooding確認結果、Androidを後続検証にした場合の記録
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）

## 9. 完了報告

- 作業日: 2026-07-08
- 読んだファイル: `AGENTS.md`、`docs/tasks/README.md`、`docs/tasks/BACKLOG.md`、`docs/02_機能仕様書.md` F-24〜F-26、`docs/03_技術仕様書.md` §3.7/§4.10/§5、`docs/07_Phase1計画書.md` §1/§4 M4-01/§5、`docs/design/ui-spec.md`、`core/storage/src/lib.rs`、`core/storage/src/schema.sql`、`app/rust/src/api.rs`、`app/lib/main.dart`、`app/lib/src/core/bridge_service.dart`、`app/lib/src/core/providers.dart`、`app/lib/src/router.dart`、`app/lib/src/screens/task_detail_screen.dart`、`app/lib/src/ui/task_components.dart`、`app/lib/l10n/app_en.arb`、`app/lib/l10n/app_ja.arb`、`app/test/support/fake_bridge_service.dart`、`app/test/visual_qa/visual_qa_screenshots_test.dart`
- 作業前退避: `app/build/visual_qa_backups/visual_qa-20260708-072339`

実装内容:

- pub依存: `flutter_local_notifications 22.0.1` を追加した。`zonedSchedule` の `TZDateTime` 直接利用と `depend_on_referenced_packages` 対応のため `timezone 0.11.1` も直接依存へ追加した。
- iOS/macOS初期化: `DarwinInitializationSettings` で初期権限要求を無効化し、初回リマインダー設定時に `requestPermissions(alert: true, badge: false, sound: true)` を呼ぶ構成にした。
- 通知カテゴリ/アクション: category id `taskveil_reminder_v1`、action id `taskveil_snooze_1h`。アクション表示は en `+1 hour` / ja `1時間後`。foreground action としてアプリ起動後に `snoozed_until` を更新して再スケジュールする。
- v6 schema: `reminders(id TEXT PRIMARY KEY NOT NULL, task_id TEXT NOT NULL, remind_at INTEGER NOT NULL, snoozed_until INTEGER, created_at INTEGER NOT NULL)`、`idx_reminders_task_id`、`idx_reminders_pending` を追加した。`LATEST_SCHEMA_VERSION` は6へ更新した。
- 新規DB経路: `schema.sql` に `reminders` 定義を追加し、v6 migration は `CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS` で既存DBと新規DB経路の両方を扱う。
- storage API: `Reminder` / `ReminderRepository` / `SqliteReminderRepository` を追加し、設定、解除、タスク別一覧、サブツリー一覧、リスト別一覧、未発火一覧、スヌーズ更新を実装した。タスク/リスト物理削除時は関連reminderも削除する。
- bridge API: `ReminderDto`、`set_task_reminder`、`clear_task_reminders`、`get_task_reminders`、`get_task_subtree_reminders`、`get_list_reminders`、`list_pending_reminders`、`snooze_reminder` を追加した。
- FRB再生成: `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、`app/rust/src/frb_generated.rs`、`app/lib/src/rust/api.dart`、`app/lib/src/rust/frb_generated.dart`、`app/lib/src/rust/frb_generated.io.dart` を更新した。
- Dart provider/API: `BridgeService` / `FrbBridgeService` / `FakeBridgeService` にreminder APIを追加し、`taskRemindersProvider`、`reminderNotificationGatewayProvider`、`reminderNotificationServiceProvider` を追加した。
- 通知ID設計: `notificationIdForReminder(reminderId)` でreminder UUID文字列から安定した31bit FNV-1a値を算出する。
- payload設計: JSON payload は `reminderId`、`taskId`、`listId` のみ。タスクタイトル、ノート、Device Key、導出鍵、exportKey等は含めない。
- タスク詳細UI: `_EditableTaskMetadata` に Lucide `bell300` のリマインダーチップを追加した。未設定時は en `Reminder` / ja `リマインダー`、設定済みはローカル日時を `DateFormat.MMMd` + `DateFormat.jm` で表示する。チップタップで日付/時刻選択、設定済みチップ内のxで解除する。
- 権限拒否時: reminder保存後にOS通知スケジュールだけ行わず、en `Notifications are off...` / ja `通知がオフです...` のSnackBarを表示する。
- l10nキー: `reminderChipEmpty`、`reminderChipTooltipSet`、`reminderChipTooltipChange`、`clearReminderButton`、`reminderPermissionDenied`、`failedToSaveReminder`、`reminderNotificationTitle`、`reminderNotificationBody`、`reminderSnoozeOneHourAction` を追加した。`flutter gen-l10n` 実行済み。
- 起動時再スケジュール: `main.dart` で `RustLib.init`、DB初期化、`initCore` 完了後に `ReminderNotificationService.initialize` と `reschedulePending` を実行する。通知初期化失敗は既存の初期化エラー画面へ入る。
- 完了/`wont_do`/削除時キャンセル: `TasksNotifier` / `HomeTasksNotifier` のclose操作で該当taskのreminderをキャンセルし、`deleteTask` でサブツリーreminder、`deleteList` でリスト配下reminderをキャンセルする。
- スヌーズ: 通知action `taskveil_snooze_1h` 受信時に同一reminderの `snoozed_until` を現在時刻+1時間へ更新し、同一payloadで再スケジュールする。
- 通知タップ遷移方針: 通常タップはアプリ起動/Home表示まで。payloadには詳細遷移に必要なIDを含めたが、起動直後にrouterとproviderのDB hydrationをまたいで詳細へ安定遷移させる処理は本タスクでは入れていない。スヌーズactionは起動後 callback で処理する。

追加・更新したテスト:

- Rust: `v5_database_migrates_to_v6_and_adds_reminders_table`、`sqlite_reminder_repository_sets_lists_clears_and_snoozes_reminders`、`sqlite_reminder_repository_lists_pending_open_tasks_only`、`sqlite_reminder_repository_lists_subtree_and_list_reminders_for_cancellation`、`task_and_list_physical_deletes_remove_reminders`
- Flutter: `task reminders are exposed through Rust bridge`、`reminder provider saves schedules and clears local notifications`、`permission denial saves the reminder without scheduling plugin work`、`snooze notification action updates reminder and reschedules it`、`startup reschedules pending reminders for open tasks`、`task detail shows a localized reminder chip`

visual QA:

- 生成コマンド: `sh tool/visual_qa.sh`
- スクリーンショット: `app/build/visual_qa/task_detail.png`
- 目視確認: `task_detail.png` で設定済みリマインダーチップ `Jul 8 4:30 PM`、解除x、既存metadataチップ、Subtasks領域の重なり・文字切れがないことを確認した。

iOS Simulator手動確認手順（親実行用）:

1. `cd app && flutter devices` または `xcrun simctl list devices available` で対象Simulatorの機種、OS、device idを記録する。
2. `cd app && flutter run -d <device id>` で起動する。
3. Homeから任意タスクを開き、リマインダーチップをタップする。
4. 通知権限ダイアログで許可する。
5. 現在時刻+2〜3分の日時を選んで保存する。
6. アプリをバックグラウンドへ送り、指定時刻に通知が出ることを確認する。
7. 同じタスクを再度開き、リマインダーチップのxで解除し、再度+2〜3分に設定してから解除後の時刻に通知が出ないことを確認する。
8. 再度+2〜3分で設定し、通知表示時に `+1 hour` / `1時間後` action を押す。DB上の同一reminderが `snoozed_until` 更新され、OS通知が再登録されることを、アプリ再起動後に該当taskのリマインダーチップ時刻またはデバッグDB確認で記録する。
9. 通知通常タップではアプリが起動しHomeへ入ることを確認する。
- 手動確認結果: 未実行（親検証対象）。

macOS / Android:

- macOS dogfooding実通知: 未実行（親検証対象）。
- Android実通知: 後続検証扱い。Android用 `AndroidInitializationSettings` / `AndroidNotificationDetails` はコンパイル維持用に設定したが、Android 13+権限やAndroid 14 exact alarmの実機確認は本タスクでは未実施。

品質ゲート:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
- `cd app && flutter analyze`: 成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter test`: 成功（111 passed, 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `cd app && sh tool/visual_qa.sh`: 成功（37 passed）
- `git diff --check`: 成功

変更ファイル:

- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`
- `app/rust/src/frb_generated.rs`
- `app/lib/src/rust/api.dart`
- `app/lib/src/rust/frb_generated.dart`
- `app/lib/src/rust/frb_generated.io.dart`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/notifications/reminder_notifications.dart`
- `app/lib/main.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/app_localizations.dart`
- `app/lib/src/generated/l10n/app_localizations_en.dart`
- `app/lib/src/generated/l10n/app_localizations_ja.dart`
- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/macos/Flutter/GeneratedPluginRegistrant.swift`
- `app/test/core_usecases_test.dart`
- `app/test/reminder_notifications_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-65-local-notifications.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

未解決事項:

- iOS Simulator/実機での実通知発火、通知取消、スヌーズ再登録、通常タップ起動の手動確認は親検証待ち。
- macOS dogfoodingでの実通知発火確認は親検証待ち。
- 通知通常タップから該当タスク詳細へ直接遷移する処理は未実装。現状はHome起動。
- Android実通知は後続検証扱い。
