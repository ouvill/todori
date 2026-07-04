# docs/tasks/ バックログ

`docs/tasks/` 配下の作業指示書と完了報告から見える現在の進捗、および次に着手すべきタスクの優先度付きリストである。新しいタスクに着手する前に必ず参照すること。

## 現在地（2026-07-04時点）

- **Phase 1 / M1（コア層）: 完了。** task-05（`core/domain` ユースケース） / task-06（`core/storage` リポジトリ） / task-07（Device Key抽象）。
- **Phase 1 / M2（ブリッジとUI骨格）: 完了。** task-08（ブリッジAPI公開） / task-09（Riverpod + go_router 画面骨格） / task-10（i18n en/ja） / task-11（CI整備）。macOSデスクトップ実行はcargokitで確立済みで、Phase 1品質ゲートはGitHub Actionsへ追加済み。
- **PoC完了済み**: task-01（OPAQUE） / task-02（SQLCipher） / task-03（FRB垂直貫通） / task-04（Phase1計画書の作成）。
- **OSS公開前監査完了済み**: task-12（秘密情報、公開不適切情報、OSS基本文書、ライセンス、public repo向けCI/Actions安全性の棚卸し）。公開判断と公開前整備は人間判断・後続タスクとして扱う。
- **iOS検証**: Simulator上で `todori-crypto` 全17テスト・`todori-storage` 全10テストが成功、実機ターゲットのリンクも成功済み（`docs/07_Phase1計画書.md` §3補足参照）。
- **テスト数**: Rust 62 / Flutter 11（いずれも最新の完了報告時点の値。着手前に最新の完了報告で更新すること）。
- **実行エージェント運用**: 「docs/tasks/指示書 → codex実装 → 品質ゲート → 完了報告追記 → コミット」のループが確立済み（task-05〜10で実績あり）。

## 優先度付きバックログ

| # | タスク | 内容 | 対応マイルストーン | 備考 |
|---|---|---|---|---|
| 1 | public/privateドキュメント分割方針 | task-12の監査結果を受け、public repoを主、private repoを内部メモ置き場とする運用に向けた文書分類と移行計画を策定する | 公開準備 | [task-13-public-private-docs-split.md](./task-13-public-private-docs-split.md) |
| 2 | iOS Simulatorでflutter run検証 | cargokitのiOS podspec実証（`app/rust_builder/ios/todori_app_bridge.podspec` 同梱済み）。macOSで踏んだ地雷は解決済みのため短期決着見込み | M2残 | Simulator起動には `xcrun simctl` を用いる。署名不要 |
| 3 | タスク編集UI | タスク詳細画面での `title`/`note`/`priority`/`due_at` 編集。ブリッジにupdate系APIを追加（FRB再生成が必要） | M3-02 | |
| 4 | サブタスク表示・作成 | `validate_parent`（`core/domain` 実装済み）のブリッジ公開とUI実装 | M3-03相当 | |
| 5 | ゴミ箱画面・復元UI | `get_trashed_tasks` / `restore_task` はブリッジ公開済み。画面とルートの追加のみ | M3-04相当 | |
| 6 | fractional index | `sort_order` 生成の本実装（`core/domain`）と並び替えUI | M3-05相当 | 現状は暫定連番（`'a0'`, `'a1'`, ...） |
| 7 | FTS5検索の配線 | `tasks_fts` の同期トリガー、またはアプリ層更新 + 検索API + （UIはPhase 3送り） | M1-02残課題 | task-02の完了報告「やらないこと」参照 |
| 8 | iOS Keychain DeviceKeyStore | 本番用DK保存。`FileDeviceKeyStore` を置き換える | M4 | セキュリティ上の必須事項 |
| 9 | ローカル通知 | F-24〜F-26。iOS先行で実装する | M4 | |

（`docs/07_Phase1計画書.md` のマイルストーン表と整合させること。表のID対応が計画書と厳密一致しない場合は「相当」と表記する。）

## 新タスク着手の手順

1. このBACKLOGと `docs/07_Phase1計画書.md` を突き合わせて次に着手するタスクを選ぶ。
2. `docs/tasks/task-NN-<slug>.md` を、既存タスク（task-05〜10が良い見本）と同じ体裁で書く: 1. 背景とコンテキスト、2. 事前に読むべきファイル、3. ゴール、4. スコープ（やること/やらないこと）、5. 実装手順（例）、6. 受け入れ基準（チェックボックス）、7. 制約・注意事項、8. 完了報告に含めるべき内容。あわせて `docs/tasks/README.md` のタスク一覧表に行を追加する。
3. 指示書をコミットしてから実装に着手する。
4. 品質ゲートを全通過させる → 指示書に「## 9. 完了報告」を追記する → Conventional Commitsでコミットする。
5. 完了後、このBACKLOG.mdの「現在地」セクションを更新する。

## 補充のルール

- このバックログは自動では増えない。PLAYBOOK.md のセッション種別6（バックログ補充）を定期的に実行して棚卸しする
- タスクの供給源は3つに限る: (1) docs/07_Phase1計画書のマイルストーン表 (2) 各タスク完了報告の未解決事項 (3) 計画書のリスク表。**出典のないタスクを積んではならない**
- 仕様の追加・変更を伴うものはバックログに直接入れず「要人間判断」に置く

## 要人間判断

（現在なし。補充セッションが仕様判断を要する項目を見つけたらここに追記する）
