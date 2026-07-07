# task-67: 性能検証（M4-04）

> ステータス: 完了（2026-07-08）
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

Phase 1計画書のM4-04は、1万件データでの起動2秒以内、主要リスト操作60fps目標、オフライン動作の検証を完了条件としている。TodoriはローカルSQLCipher DBとFlutter UIを中心に動作するため、Phase 2同期へ進む前にローカル性能の基準値を記録する。

本タスクは検証系タスクである。軽微な最適化（インデックス追加、テスト専用seed、計測用widget test）は実施してよいが、大規模なデータロード再設計やUI仮想化方針変更は要人間判断として完了報告へ送る。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M4-04
- `docs/02_機能仕様書.md` F-50〜F-52
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/support/fake_bridge_service.dart`

## 3. ゴール

- 1万件（リスト10×タスク1000）の現実的分布seedをテスト専用に生成できること。
- シード済み暗号化DBに対して `get_today_tasks` 相当（Home横断取得）、`get_tasks`、`search_tasks`、migration適用、`init_core + 初期クエリ` 相当の実行時間を計測し、数値を記録すること。
- Flutter層はwidget testで大量データpump時間を計測し、`flutter run --profile` の人間実行手順を残すこと。
- ネットワーク無依存でオフライン動作することを確認し、現状の依存範囲を記録すること。
- 1万件時の顕在ボトルネックと、実施した軽微な最適化または要人間判断事項を記録すること。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/test/support/fake_bridge_service.dart`
- `app/test/performance_large_data_test.dart`
- `docs/tasks/task-67-performance-verification.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. 1万件seedを生成するRustテスト専用ユーティリティを追加する。
2. シード済み暗号化DBでRust層のクエリ計測を行う ignored test を追加し、CI通常テストには重い性能計測を混ぜない。
3. 起動2秒以内の近似として、`open_encrypted` + `ensure_default_list` + `list_all` + `list_home` を計測する。
4. migration適用はseed済みv3 DBから最新スキーマへのopen時間として計測する。
5. Flutter fake bridgeへ大量データseed helperを追加し、Homeと単一リスト画面のpump時間をwidget testで計測する。
6. 1万件時のHome横断クエリ、単一リスト取得、検索、migrationの数値を完了報告へ表で残す。
7. 軽微な最適化を行った場合は、変更内容とbefore/afterまたは観測理由を完了報告に記録する。
8. 品質ゲートを実行し、実行不能なものは環境起因を明記する。

### やらないこと

- 本番UIの大規模な再設計。
- Phase 2同期、サーバー、ネットワーク通信の実装。
- 新規依存追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更。
- git commit。

## 5. 実装手順（例）

1. `git status --short` で作業前状態を確認する。
2. 指定ドキュメントと `core/storage`、起動時provider経路、fake bridgeを読む。
3. `core/storage` の `#[cfg(test)]` 内に性能seed helperと ignored timing test を追加する。
4. 必要ならクエリ計画を確認し、インデックス追加など軽微な最適化を実施する。schema変更時はmigrationとテストを追加する。
5. `FakeBridgeService` にテスト専用の大量seed helperを追加する。
6. `app/test/performance_large_data_test.dart` を追加し、pump時間を `debugPrint` と期待値で記録する。
7. Rust ignored testを明示実行し、出力された計測値を完了報告へ転記する。
8. Flutter widget testを実行し、出力されたpump時間を完了報告へ転記する。
9. 品質ゲートを実行する。
10. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] Rustテスト専用ユーティリティで、リスト10×タスク1000、階層・期日・完了状態が混在する1万件seedを生成できる。
- [ ] シード済み暗号化DBで `get_today_tasks` 相当、`get_tasks`、`search_tasks`、migration適用、起動近似時間の計測値が完了報告に表で記録されている。
- [ ] 起動近似時間が2秒を超える場合、ボトルネックと軽微な最適化可否または要人間判断が記録されている。
- [ ] Flutter widget testで大量データpump時間が計測され、数値が完了報告に記録されている。
- [ ] `flutter run --profile` による人間実行用の手動計測手順が完了報告に記録されている。
- [ ] オフライン動作について、現状ネットワーク依存がないことの確認結果が完了報告に記録されている。
- [ ] 1万件時の顕在問題（Home横断クエリ等）があれば、計測値とともに未解決事項へ記録されている。
- [ ] README/BACKLOGのtask-67状態が更新されている。

## 7. 制約・注意事項

- 性能計測は端末・負荷に依存するため、数値には実行環境を併記する。
- cargo benchは不要。Rust層はテスト内の `Instant` 計時でよい。
- 重い性能計測は通常の `cargo test --workspace` を遅くしないよう ignored test にする。
- Flutter profile実測は環境制約があるため、widget test計測と人間実行手順の記録に留めてよい。
- Rust APIを変更した場合のみFRB再生成を行う。テスト専用変更では生成物に触れない。
- migrationやschemaを変更する場合は既存DBから最新への移行テストを追加する。
- 本番コードに計測ログや性能seedを混ぜない。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 実行環境（OS、Rust/Flutterの確認可能な範囲）
- 1万件seedの分布（リスト数、タスク数、階層、期日、ステータス）
- Rust層計測結果表（操作、件数、経過時間、備考）
- Flutter widget test計測結果表（画面、件数、pump時間、備考）
- `flutter run --profile` 手動計測手順
- 起動2秒以内の評価結果
- ボトルネックと実施した軽微な最適化
- オフライン動作確認結果
- 変更ファイル一覧
- 品質ゲート実行結果
- 未解決事項（なければ「なし」）

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M4-04
- `docs/02_機能仕様書.md` F-50〜F-52
- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/home_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/support/fake_bridge_service.dart`

実行環境:

- macOS 26.5.1 (25F80)
- rustc 1.96.0 (ac68faa20 2026-05-25)
- cargo 1.96.0 (30a34c682 2026-05-25)
- Flutter 3.44.4 stable / Dart 3.12.2

1万件seedの分布:

- Rust層: リスト10、タスク10000、期日あり6667、closed 2000。各リスト1000件、root 700件、child 220件、grandchild 80件。ステータスは `done` 10%、`wont_do` 10%、`in_progress` 20%、`todo` 60%。期日はなし、昨日、今日、明日、翌週を混在。検索語は `alpha`、`日本語`、`routine` を混在。
- Flutter fake層: Rust層と同じリスト数、タスク数、階層、期日、ステータス分布でseed。

Rust層計測結果（`cargo test -p todori-storage task_67_reports_10000_task_storage_timings -- --ignored --nocapture`）:

| 操作 | 件数 | 経過時間 | 備考 |
|---|---:|---:|---|
| get_today_tasks相当 (`list_home`) | 7140 | 134ms | encrypted DB、全リスト横断Home query |
| get_tasks (`list_active_by_list`) | 1000 | 3ms | 単一リスト1000件 |
| search_tasks (`alpha`) | 589 | 10ms | FTS5 prefix query |
| migration (`v3_to_latest`) | 10000 | 61ms | v4 FTS backfill + v5-v7 migrations |
| 起動近似 (`open_encrypted` + default list + lists + archived + Home) | 7140 | 123ms | `init_core + 初期クエリ` 相当のRust storage近似 |

Flutter widget test計測結果:

| 画面 | 件数 | pump時間 | 備考 |
|---|---:|---:|---|
| Home | total 10000 / Home表示scope 7140相当 | 21304ms | `flutter test test/performance_large_data_test.dart --reporter expanded` 単体実行 |
| Tasks | total 10000 / 単一リスト1000 | 1019ms | 同上 |
| Home | total 10000 / Home表示scope 7140相当 | 22516ms | `flutter test --reporter expanded` 全体test内 |
| Tasks | total 10000 / 単一リスト1000 | 1010ms | 同上 |

`flutter run --profile` 手動計測手順:

1. `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`
2. `cd app && flutter run --profile -d macos`
3. 起動後、DevTools Performanceで初回frame、Home初期表示、単一リスト遷移、検索導線追加後は検索操作を計測する。
4. 1万件実データを入れたDBで、Home、単一リスト、スクロール、チェック操作のframe chartとjankを記録する。

起動2秒以内の評価結果:

- Rust storage近似の起動計測は123ms。2,000ms未満。
- Flutter widget testのHome初期pumpは21304ms/22516ms。これはfake bridge + widget test環境のbuild/pump時間であり、Rust storage起動近似とは別のUI層計測値として記録。

ボトルネックと実施した軽微な最適化:

- Rust storageではHome横断取得が7140行を返す。`tasks(list_id, sort_order, id)` と `tasks(due_at, status, completed_at, list_id) WHERE due_at IS NOT NULL` のindexをv7 migrationとbaseline schemaへ追加した。
- Flutter fake bridgeではHome ancestor探索が `_tasks.firstWhere` による線形探索を繰り返していたため、`taskById` mapを使う形に変更した。
- Flutter Home widget testでは、1万件seed時にHome scope 7140相当の行をpumpするため、Home初期pumpが21秒台となった。UI仮想化、Home取得件数制限、セクション別遅延構築などの設計変更は本タスク範囲外として未実施。

オフライン動作確認結果:

- `app/lib`、`app/test`、`core` に対し `dart:io`、URL文字列、HTTP/Dio/Socket/WebSocket系の参照をgrep確認した。該当はローカルfilesystem用途の `dart:io` とコメント内URLのみ。
- Phase 1の実装範囲では、同期機能を除く主要操作はローカルSQLCipher DB、FRB、ローカル通知pluginに閉じていることをソース確認した。

変更ファイル一覧:

- `core/storage/src/lib.rs`
- `core/storage/src/schema.sql`
- `app/test/support/fake_bridge_service.dart`
- `app/test/performance_large_data_test.dart`
- `docs/tasks/task-67-performance-verification.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

品質ゲート実行結果:

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（`task_67_reports_10000_task_storage_timings` ignored 1件、real Keychain ignored 1件は既存方針どおり）。
- `cd app && flutter analyze`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test --reporter expanded`: 成功（116 passed、visual QA harness 1 skipped）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `git diff --check`: 成功。
- `cargo test -p todori-storage task_67_reports_10000_task_storage_timings -- --ignored --nocapture`: 成功。
- `cd app && flutter test test/performance_large_data_test.dart --reporter expanded`: 成功。

未解決事項:

- Flutter Homeの1万件fake seed初期pumpは21秒台。Homeがサブツリー/祖先同伴により7140行相当を初期構築することが顕在ボトルネック。
- `flutter run --profile` による実機/profileのframe chart取得は手順記録まで。本セッションでは実アプリprofile計測は未実施。
