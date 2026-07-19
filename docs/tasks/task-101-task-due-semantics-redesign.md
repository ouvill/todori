# task-101: 日付期限と日時締切の意味論再設計

> ステータス: 完了（日付期限 / 日時締切をtyped unionへ分離）
> 作業日: 2026-07-12

## 1. 背景とコンテキスト

現行taskは`due_at: Option<i64>`だけを持ち、日付だけを選んだ場合もローカル日の開始epochを保存する。この表現では「この日までに」と「この時刻までに」を判別できず、timezone変更で日付意図がずれる。`scheduled_at`は開始予定、`remind_at`は通知であり、期限の代用にはできない。

ADR-017は、期限を`未設定 / 日付のみ / 日時指定`の排他的なtagged unionへ置き換えると定め、2026-07-12にプロダクトオーナーが承認した。本taskはAccepted済みADR-017を実装する重要変更taskである。現行schema・wire・開発データとの互換性は要件とせず、旧値の推測変換は行わない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/STATUS.md` / `README.md` / `PLAYBOOK.md` / `BACKLOG.md`
- `docs/03_技術仕様書.md` §3.6 / §3.7 / §6.3
- `docs/05_設計判断記録.md` ADR-012 / ADR-014 / ADR-017
- `docs/02_機能仕様書.md` F-12（変更は人間承認後のみ）
- `core/domain/src/entities.rs` / `usecases.rs`
- `core/storage/src/schema.sql` / `lib.rs`
- `core/sync/src/field_map.rs` / `merge.rs` / `apply.rs`
- `core/client/src/runtime/application.rs` / `mutation_service.rs`
- `app/rust/src/api.rs`、FRB configと生成物
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/screens/tasks_screen.dart` / `task_detail_screen.dart`
- `app/lib/src/ui/task_components.dart`

## 3. ゴール

- 「この日までに」と「この時刻までに」をdomain型から判別できる。
- 日付のみ期限がtimezone変更やDSTで別日へずれない。
- 日時指定期限が一意なinstantと入力timezoneを保持し、時刻単位で期限切れ判定できる。
- DB、同期field clock、client / FRB、Dart、Today / sort、作成・編集UIが同じtagged union契約を使う。
- `scheduled_at`、`remind_at`、期限の3概念を混同しない。

## 4. スコープ

### やること

- Accepted済みADR-017を正本として、`docs/03_技術仕様書.md`のtask schema、同期plaintext、Today判定を同期する。
- domainへ検証済み`CivilDate`、`UtcInstant`、`IanaTimeZone`と`TaskDue` tagged unionを追加する。
- local DBを`due_kind` / `due_on` / `due_at_ms` / `due_time_zone` + CHECK constraintへbreaking更新し、Home query / index / sortを更新する。
- sync plaintextを`due: Clocked<Option<TaskDue>>`へbreaking更新し、merge、apply、enqueue、strict decode testを更新する。
- `taskveil-client`とFRBをtyped due input / DTOへ置き換え、FRB生成物を正規手順で再生成する。
- Flutterの作成・編集UIに「日付のみ / 日時指定」を追加し、表示、semantics、Today / overdue分類、sortを更新する。
- 英日ARB、fake bridge、widget test、visual QAを新契約へ更新する。
- 旧開発profile / serverデータの再作成手順とprotocol version gateを記録する。

### やらないこと

- 旧`due_at`値の変換、00:00からの種別推測、dual read/write、互換fallback。
- `scheduled_at`と期限の統合、Focus planやcalendar schedulingの再設計。
- reminderの新規UI、繰り返しtask、自然言語日付入力。
- Organization固有timezone policy、共有相手ごとの表示timezone固定。
- public/private境界外の事業・法務情報変更。

## 5. 実装手順

1. Accepted済みADR-017の契約を確認し、`docs/01` / `docs/02`を変更する場合の人間承認範囲を明示する。
2. domain型とserialization shapeを先に固定し、invalid date、unknown timezone、DST gap / fold、範囲外instantのerror契約をtest化する。
3. baseline schemaと最新migrationをbreaking更新し、CHECK constraint、Home query、index、repository round-tripをtestする。
4. syncの`due` compound field、strict decode、field-clock merge、CAS stale merge/retryを更新し、date / datetime切替競合をtestする。
5. `taskveil-client`のcreate / update / undoをtyped dueへ変更し、domain更新 + HLC + outboxが同一transactionであることを維持する。
6. FRB APIをtyped due DTOへ変更してcodegenし、Dart bridgeとfakeを追従させる。
7. 作成sheet、詳細編集、task row、Today / overdue、sortを新意味論へ変更し、timezone差とDST境界をwidget test化する。
8. 旧開発profile / serverデータを再作成して2-device同期を確認し、visual QAと全品質ゲートを実行する。
9. 実装非担当の検証者がADR-017、技術仕様、DB constraint、sync payload、UI観測結果を独立検証する。

## 6. 受け入れ基準

- [x] `TaskDue`が`None`、`Date(CivilDate)`、`DateTime(UtcInstant, IanaTimeZone)`以外の状態を表現できない。
- [x] `CivilDate`のround-tripでtimezone変換を一度も行わず、端末timezone変更後も同じ`YYYY-MM-DD`を表示する。
- [x] 日付のみは翌local dateになるまで期限切れにならず、日時指定は`now >= due_at`で期限切れになる。
- [x] DST gapの存在しないlocal timeを拒否し、foldの曖昧なlocal timeはユーザーがoffsetを判別できるか決定的policyで解決する。
- [x] viewer timezoneと入力timezoneが異なる日時指定を曖昧でない表示にする。
- [x] DB CHECK constraintがmixed / partial due columnsを拒否し、date / datetime / nullのrepository round-tripが成功する。
- [x] Home queryが日付のみと日時指定を正しくToday / overdueへ分類し、同日内で未来の日時指定を時刻順、日付のみをその後へ並べる。
- [x] sync plaintextが期限全体へ1つのHLCを持ち、別端末のdate↔datetime競合後にmixed stateを生成しない。
- [x] unknown tag、invalid date、invalid timezone、欠落field、旧payloadをfail closedで拒否する。
- [x] create / update / undoで期限変更、HLC、record state、outboxが同一transactionに残る。
- [x] FRB / Dart APIがraw epochだけを期限として受け渡さず、期限kindを型から判別できる。
- [x] 作成・編集UIで「日付のみ / 日時指定 / 期限なし」を切り替えられ、task rowは日付のみへ時刻を表示しない。
- [x] `scheduled_at`と`remind_at`の意味・保存・既存通知が期限変更で壊れない。
- [x] 英日ARB、tooltip、semantics、48px級tap target、text scale 2.0を満たす。
- [x] date-only timezone変更、datetime timezone換算、DST gap / fold、midnight exact deadline、Today境界のfocused testがある。
- [x] 旧profile / old protocolを暗黙に読み続けず、再作成またはversion gateで明示的に停止する。
- [x] `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`が成功する。
- [x] `cd app && flutter analyze`、release Rust build後の`flutter test`、hardcoded strings / client boundaries / `git diff --check`が成功する。
- [x] visual QAを全件目視し、日付のみ、日時指定、timezone差、期限切れ、狭幅、日本語、text scale 2.0に描画異常がない。
- [x] 独立検証でP1 / P2指摘がない。

## 7. 制約・注意事項

- ADR-017 Accepted前に実装へ入らない。裁定で意味論が変わった場合は本taskの1〜8章を先に更新する。
- DBの`due_at_ms`はstorage detailであり、domain / FRB / Dartへraw integer契約を漏らさない。
- timezoneは固定offsetでなくIANA IDを保持する。timezone database更新で将来規則が変わっても、保存済み`due_at` instantは変更しない。
- date / datetimeのtagとpayloadを別field clockへ分割しない。
- unknown / legacy sync payloadを推測補完しない。復号済みplaintextやtask内容をerror logへ含めない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md`の変更には人間承認が必要である。
- FRB生成物は手編集せず、`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`を使う。

## 8. 完了報告に含めるべき内容

- Accepted ADRの最終契約と、日付のみ / 日時指定 / scheduled / reminderの意味の違い。
- domain型、DB列とCHECK constraint、schema / protocol version、sync plaintext shapeとfield-clock単位。
- timezone、DST gap / fold、Today / overdue / sortの実装規則とtest名。
- FRB codegen、UI / ARB、visual QAのbefore / afterと全PNG目視所見。
- 開発profile / serverデータ再作成手順、互換layerがないこと、2-device同期結果。
- 全品質ゲート、独立検証の判定・指摘、commit hash、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-12
- 結果: 期限を`未設定 / 日付のみ / 日時指定`の排他的な`TaskDue`へ置き換えた。日付のみはtimezoneを持たない`CivilDate`、日時指定は`UtcInstant + IanaTimeZone`として保持し、`scheduled_at`とreminderは別概念のまま維持した。
- DB / sync: local schemaをv17へ更新し、`due_kind / due_on / due_at_ms / due_time_zone`のCHECK constraintを追加した。sync protocolをv4、envelopeをv3へ更新し、`due: Clocked<Option<TaskDue>>`を1つのatomic fieldとしてmergeする。
- timezone / UI: IANA zoneのlocal wall timeからinstantを生成し、DST gapは拒否、foldは決定的なinstantを選んでIANA IDとUTC offsetを表示する。作成sheet、詳細、swipe期限変更、Today / overdue / sort、英日ARBをtyped dueへ更新した。Today分類は`期限超過 > scheduled_atが本日 > 残りの期限section`の優先順位とし、dueとscheduledの併存時も重複表示せずscheduled Todayを維持する。
- 互換性: v16の空DBだけをv17へ移行する。taskを持つv16 profileは値を推測せずopenを停止してprofile再作成を要求し、旧sync payloadもprotocol / envelope version gateで停止する。互換layer、dual read/write、midnight推測はない。
- 再作成手順: アプリを終了し、開発端末のApplication Support配下にある`taskveil-db` profile directoryを削除して再起動する。local server dataは`docker rm -f taskveil-dev-postgres`後に`tool/dev_server.sh`で再作成する。本番データには適用しない。
- 証拠: `due_values_validate_and_roundtrip_as_tagged_union`、`v16_empty_database_migrates_to_typed_due_and_rejects_mixed_shape`、`v16_profile_with_ambiguous_due_data_requires_recreation`、`due_mode_switch_merges_as_one_atomic_field`、`production_two_client_distinct_fields_and_due_mode_conflict_converge`、`task_due_test.dart`、`create sheet stores an exact deadline with IANA time zone`が成功した。server経由2-client testではAのDateとBのDateTime競合後にBの後発値へ両local DBが収束した。
- iOS Simulator: iPhone 17 / iOS 26.5へ`flutter run --debug`でbuild・install・launchした。残存v16 profileは`replace_task_due_semantics`が設計どおり再作成要求で停止し、Simulator上のTaskveilをuninstallして再install後、fresh v17 profileでnative core初期化エラーなくオンボーディングを描画し、Application Support配下へ`taskveil-db/taskveil.db`が作成された。Simulator操作を自動化するintegration test / IDB / Maestro基盤は未導入のため、これは起動・migration・fresh profileのsmoke testである。
- Visual QA: `sh app/tool/visual_qa.sh`は57 test成功、63 PNGを全件目視した。`task_due_mode_sheet.png`とforeign IANA zoneを含むHome fixtureで、日付のみ / 日時指定、期限切れ、狭幅、日本語、dark、text scale 2.0に描画異常なし。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker統合testを含む`cargo test --workspace`、`flutter analyze`、release Rust build後の`flutter test`（143成功、visual QA harness 1件は通常実行でskip）、hardcoded strings、client boundaries、`git diff --check`が成功した。
- FRB: `TaskDueInput` / `TaskDueDto`を`Date { dueOn }` / `DateTime { dueAt: DateTime, timeZone }`のFreezed sealed unionとして`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`で生成した。`kind: String`、nullable product shape、`dueAtMs`はDart期限APIに存在しない。
- Commit: `fe551af`（`feat(tasks): separate date and datetime deadlines`）。
- 未解決: 実端末2台でのprofile再作成後同期確認は未実施。iOS Simulator fresh profile smoke testと、server経由2-client期限競合・両local DB収束testで自動化可能範囲を確認した。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 実装非担当サブエージェントが統合差分とADR-017 / F-12 / task受け入れ条件を照合し、初回P2 2件（scheduled-only Today、FRB / Dart product型）と再検証P2 1件（due + scheduled併存時のToday優先）を指摘した。全3件の修正後、`期限超過 > scheduled Today > 残りの期限section`、Freezed sealed union、server経由date↔datetime競合と両DB収束を再確認した。
- 再実行: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker / server統合18件を含む`cargo test --workspace`、release Rust bridge build、`flutter analyze`、full `flutter test`（143成功、Visual QA harness 1件は通常実行でskip）、hardcoded strings、client boundaries、`git diff --check`が成功した。Visual QAは別途57 test成功、63 PNG目視済み。
- 補足: 実端末2台同期は未実施だが、独立検証者は自動server経由2-client期限競合testを代替証拠としてtask完了可能と判定した。
- 検証者: 実装非担当サブエージェント `/root/task101_independent_verification`
