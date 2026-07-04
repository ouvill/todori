# docs/tasks/ バックログ

`docs/tasks/` 配下の作業指示書と完了報告から見える現在の進捗、および次に着手すべきタスクの優先度付きリストである。新しいタスクに着手する前に必ず参照すること。

## 現在地（2026-07-05時点）

- **Phase 1 / M1（コア層）: 完了。** task-05（`core/domain` ユースケース） / task-06（`core/storage` リポジトリ） / task-07（Device Key抽象）。
- **Phase 1 / M2（ブリッジとUI骨格）: 完了。** task-08（ブリッジAPI公開） / task-09（Riverpod + go_router 画面骨格） / task-10（i18n en/ja） / task-11（CI整備）。macOSデスクトップ実行はcargokitで確立済みで、Phase 1品質ゲートはGitHub Actionsへ追加済み。
- **PoC完了済み**: task-01（OPAQUE） / task-02（SQLCipher） / task-03（FRB垂直貫通） / task-04（Phase1計画書の作成）。
- **OSS公開前監査完了済み**: task-12（秘密情報、公開不適切情報、OSS基本文書、ライセンス、public repo向けCI/Actions安全性の棚卸し）。現在のGitHub repositoryはpublicであり、quiet public / pre-releaseとして扱う。
- **public/private分割方針完了済み**: task-13（public repoを主、private repoを非公開資料側とする分類と移行計画）。実分割はtask-14で完了済み。
- **public/private分割完了済み**: task-14（公開版の課金・法務要約、READMEリンク整理、private repo `todori-private` への詳細版退避）。public repository visibilityはGitHub上で人間作業により有効化済み。
- **security policy整備済み**: task-15で `SECURITY.md`、README/CONTRIBUTING導線、private vulnerability reporting利用方針を追加済み。GitHub private vulnerability reportingはGitHub上で人間作業により有効化済み。
- **品質ゲート復旧済み**: task-16で `flutter analyze` がmacOS build artifact内の古いcargokit参照を拾う問題を調査し、`app/analysis_options.yaml` の `build/**` 除外で復旧した。
- **iOS検証**: Simulator上で `todori-crypto` 全17テスト・`todori-storage` 全10テストが成功、実機ターゲットのリンクも成功済み（`docs/07_Phase1計画書.md` §3補足参照）。
- **iOS Flutter実行検証済み**: task-17で iPhone 15 Pro Simulator（iOS 17.0）上の `flutter run --debug` が成功。CocoaPods / Cargokit / Xcode build / FRB loader / SQLCipher DB作成まで到達し、`app/ios/Podfile.lock` とPods接続済みworkspace/projectを追加した。Swift Package Manager未対応警告は後続検討事項。
- **タスク編集UI実装済み**: task-18でタスク詳細画面から `title` / `note` / `priority` / `due_at` を編集し、FRB更新API経由でDBへ永続化できるようにした。priorityは `0..3`、due dateは設定/クリアに対応。
- **サブタスク表示・作成実装済み**: task-19で親ID付き `create_task`、3階層以上の階層表示、子孫全体の進捗表示、詳細画面からのサブタスク作成、未完了子孫がある親完了時の確認ダイアログを追加した。
- **UI基盤整備済み**: task-20で `ThemeData`、共通task row/metadata、空状態、loading/error、入力/確認ダイアログの小さな共通部品を追加し、Lists / Tasks / TaskDetail の見た目と文法を整理した。
- **視覚方向性反映済み**: task-21で参考画像由来の深いグリーン/淡いセージ/白いsurface、priority dot、pill metadata、サブタスク階層線、ローカル保護シグナルを既存UI foundationへ反映した。
- **デザイン方向性スケッチ完了済み**: task-22で、主要画面・空状態/ダイアログ・ゴミ箱/復元・フォーカスタイマー・完了状態の画像モックを作成し、`docs/design/visual-direction.md` に実装可能なデザインルールを整理した。キャラは空状態/オンボーディング中心、暗号化マークはメインUI常駐なし、タスク一覧は雰囲気より実用密度を優先する方針とした。
- **ゴミ箱画面・復元UI実装済み**: task-23で `/trash` route、Tasks画面からのゴミ箱導線、`trashedTasksProvider`、削除済みタスク一覧、復元action、empty/loading/error、en/ja i18n、widget testを追加した。復元後は元リストのactive task一覧も更新される。
- **fractional index・タスク手動並び替え実装済み**: task-24で `core/domain` に決定的なfractional index生成を追加し、Rust bridgeの `create_task` をRust/domain側生成へ移行した。`reorder_task` API、FRB生成物、Dart bridge/provider/fake、Tasks画面の同一階層内上/下移動UI、en/ja i18n、domain/FRB/widget testを追加した。Undo、条件ソートUI、リスト並び替えは後続タスクへ分離した。
- **UI較正完了済み**: task-25で、AI生成画像・画像モックをピクセル完全基準にせず、既存実画面の密度、長いタイトル、i18n、Dynamic Type、狭い画面、タップ領域、tooltip/semanticsを優先する較正を実装した。`docs/design/visual-direction.md` にCalibration Ruleを追加し、Tasks画面の常設保護シグナルを外し、長文/狭幅/Dynamic Type向けwidget testを追加した。Undo・条件ソートUIは後続タスクへ継続し、その後に実アプリUIの見た目をプロダクト品質へ引き上げるpolish taskを行う。
- **テスト数**: Rust 70 / Flutter 30（task-25独立検証時点の値。着手前に最新の完了報告で更新すること）。
- **実行エージェント運用**: 「docs/tasks/指示書 → codex実装 → 品質ゲート → 完了報告追記 → コミット」のループが確立済み（task-05〜10で実績あり）。

## 優先度付きバックログ

| # | タスク | 内容 | 対応マイルストーン | 備考 |
|---|---|---|---|---|
| 1 | Undo | 削除/完了/編集のUndo。履歴データ構造、操作単位、復元時の競合方針を定めて実装する | M3-05残 | `docs/07_Phase1計画書.md` M3-05、task-24完了報告の分離事項。指示書: `docs/tasks/task-26-undo.md` |
| 2 | 条件ソートUI | 手動順と締切/優先度/作成順ソートの切替UI。切替状態と設定保存方針も含めて整理する | M3-05残 | `docs/07_Phase1計画書.md` M3-05、task-24完了報告の分離事項 |
| 3 | Visual polish / product UI refinement | Lists / Tasks / Detail / Trash / Dialog / Empty state を、実データで破綻しないままTodoriらしい完成度へ引き上げる。タイポグラフィ、余白、surface、icon、空状態、操作感、App Store/READMEスクリーンショット前の第一印象をまとめて磨く | M3 polish | ユーザー判断（2026-07-05）とtask-25後のUI較正結果由来。Undo・条件ソートUIで操作密度が固まった後に実施 |
| 4 | FTS5検索の配線 | `tasks_fts` の同期トリガー、またはアプリ層更新 + 検索API + （UIはPhase 3送り） | M1-02残課題 | task-02の完了報告「やらないこと」参照 |
| 5 | iOS Keychain DeviceKeyStore | 本番用DK保存。`FileDeviceKeyStore` を置き換える | M4 | セキュリティ上の必須事項 |
| 6 | ローカル通知 | F-24〜F-26。iOS先行で実装する | M4 | |

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
