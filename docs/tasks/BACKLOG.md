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
- **Undo実装済み**: task-26でローカルSQLCipher DB内の `task_undo_entries`、削除/完了/編集のUndo履歴作成、競合検出、最新履歴取得/適用API、SnackBar action、Dart provider/fake、Rust/storage/API・Dart/FRB統合・widget testを追加した。条件ソートUI、手動並び替えUndo、複数段Undo/Redo、履歴一覧画面は後続へ分離した。
- **条件ソートUI実装済み**: task-27でTasks画面に手動順 / 締切順 / 優先度順 / 作成順の表示順切替を追加した。条件ソートは表示順のみを切り替え、`sort_order`、Rust/DB/FRB/schema、永続設定は変更していない。
- **Visual polish完了済み**: task-28でLists / Tasks / Detail / Trash / Dialog / Empty stateの第一印象をApp Store/READMEスクリーンショット前のプロダクト品質へ引き上げた。独立検証後の状態同期修正でREADME/BACKLOGの完了状態も更新済み。
- **Product experience alignment完了済み**: task-29で、起動直後をListsではなく既定リストのTasks体験へ変更し、rootにToday header / pending count / list名pill / Add task actionを追加した。Lists画面は管理/切替画面へ再位置付けし、`todori-design-direction-mobile-focus-tasks.webp` / `todori-design-direction-lists.webp` のtask-first構造へ寄せた。Focus timer、検索、スマートリスト、件数badge、装飾イラストは未実装機能として別タスク扱い。
- **visual QAスクリーンショット基盤整備済み**: task-28の使い捨て目視QAを恒久化した。`app/test/visual_qa/` + `app/tool/visual_qa.sh` を新設し、FakeBridgeServiceを共有化、`TODORI_VISUAL_QA=1` ゲートでCIへ影響しない形で実行できるようにした。
- **design mood alignment完了済み**: task-30でLora/Interのブランドタイポグラフィを導入し、タスク行のStatus/Priorityチップ削除と相対日付化、行密度圧縮、円形チェックボックスを行った。Task detail画面のLocal protectionチップ削除とCreated at表示バグ修正も行った。before/afterスクショで参照画像の雰囲気への到達を確認済み。
- **Trash visual refinement完了済み**: task-31でTrash行の削除日/期限日を短縮・相対日付文法へ揃え、visibleなPriorityチップをpriority dotへ置き換えた。FakeBridgeServiceの時刻seedを現実的なepoch millisecondsへ更新し、dark themeのpriority dot確認用 `home_tasks_dark.png` をvisual QAに追加した。
- **Task list interaction refinement完了済み**: task-32で `/lists` の左方向transition、下部折りたたみ `Completed` セクション、タスク一覧のサブタスク進捗バッジ非表示、task row / Trash row / Task detail headerのpriority dot中央揃えを行った。
- **Flutter Design Lab完了済み**: task-33で本番route/provider/DB/FRB/Rust APIに触れず、visual QA上に `design_lab_today_calm.png` / `design_lab_today_dense.png` / `design_lab_smart_lists.png` を生成するtest-onlyモック基盤を追加した。
- Design Lab方向性裁定済み（2026-07-06人間裁定: calm発展形の単一方向へ集約。詳細は `docs/design/ui-spec.md` 裁定済み事項参照）。
- タイポグラフィ裁定済み（2026-07-06人間裁定: D案構成採用・和文はシステムフォント・Lora退役。詳細はui-spec.md）。
- **typography rollout完了済み**: task-34でNewsreader範囲制限＋システム和文セリフを本番`theme.dart`へ反映し、Loraをpubspecから外した（アセットは比較用に残置）。
- **テスト数**: Rust 74 / Flutter 38（task-33実装セッション時点の値。visual QA harnessは `TODORI_VISUAL_QA=1` で11スクリーンショットを生成）。
- **Phase1計画とのギャップ棚卸し（2026-07-06親棚卸し）**: `docs/07_Phase1計画書.md` のマイルストーン表と実装状況を突き合わせ、リスト名称変更/削除UI（M3-01）とwont_do/再オープンのUIステータス遷移（M3-04）が未実装であることを確認した。バックログへ反映済み。
- **実行エージェント運用**: 「docs/tasks/指示書 → codex実装 → 品質ゲート → 完了報告追記 → コミット」のループが確立済み（task-05〜10で実績あり）。
- 2026-07-06人間裁定: ダークモードは直近スコープ外（Phase 1はライトのみ正式サポート）、オンボーディングは実装する、DBスキーママイグレーション機構は整備する。
- 2026-07-07人間裁定（データ保持原則）: 完了済みタスクはリスト削除で失われない。リスト削除は論理削除+完了履歴保全へ変更され、task-35（改名のみ）/task-36（マイグレーション機構）/task-37（リスト削除）に再編。
- 2026-07-07人間裁定（削除モデル: ゴミ箱廃止・恒久削除＋警告・削除Undoなし・完了/編集Undo維持・アーカイブPhase 1導入。docs/05 ADR-009 / docs/02 F-07・F-09改訂）

## 優先度付きバックログ

| # | タスク | 内容 | 対応マイルストーン | 備考 |
|---|---|---|---|---|
| 1 | リスト名称変更UI（task-35） | リスト作成に加え、名称変更をUIから実行できるようにする（必要ならbridge API追加も含む） | M3-01 | 出典: M3-01完了条件（作成/名称変更/削除のうち作成のみ実装済み。2026-07-06親棚卸しで確認）。task-35として着手。削除は2026-07-07人間裁定（データ保持原則）によりセマンティクスが変わるためtask-37へ分離 |
| 2 | wont_do / 再オープンのUIステータス遷移 | `done` / `wont_do` / 再オープンの各ステータス遷移をUIから実行できるようにする。禁止遷移は表示上選べないこと | M3-04 | 出典: M3-04（現行UIはラベル表示のみ。domain/Rust側にはwont_doが存在。2026-07-06親棚卸しで確認） |
| 3 | DBスキーママイグレーション機構の整備（task-36） | `core/storage` にスキーマバージョニングとマイグレーション実行機構を整備し、誤鍵/旧版DBのテストを追加する | M4前提（core/storage） | 出典: 2026-07-06人間裁定（要人間判断→確定）。設定値の永続化（#10）を含む以後のスキーマ変更をすべてマイグレーション経由にするための前提。task-37アーカイブの前提（`lists.archived_at` 追加が最初のマイグレーション題材） |
| 4 | リストのアーカイブ/解除（task-37） | リストのアーカイブ（`lists.archived_at`）/アーカイブ解除を実装する。アーカイブ済みリストは通常一覧から分離表示（アーカイブ済みセクション等）し、データ・完了履歴は完全保全する（F-09改訂準拠） | M3-01相当 | 出典: 2026-07-07人間裁定（削除モデル）。docs/02 F-09改訂準拠。task-36（DBスキーママイグレーション機構）完了後に着手 |
| 5 | ゴミ箱廃止と恒久削除への移行（task-38） | trash UI/route/API（task-23実装分）を撤去し、タスク・リストの削除を物理削除＋不可逆警告の追加確認へ移行する。削除Undoは廃止する（完了/編集Undoは維持）。`tasks.deleted_at`カラムおよびundo履歴の削除系エントリの整理はマイグレーション経由で行う | M3-01 / M3-05相当 | 出典: 2026-07-07人間裁定（削除モデル）。docs/05 ADR-009 / docs/02 F-07改訂準拠。task-37（リストアーカイブ）の直後に着手 |
| 6 | タスク行のdot/チェック整列修正 | priority dotとチェックをタイトル1行目とセンター整列させる（行全体センターではない） | 軽量レーン | 出典: 親レビュー2026-07-06（`docs/design/ui-spec.md` セクション5「既知の逸脱」参照） |
| 7 | 本番UIのアイコンをLucideへ統一 | `app/lib/` 全画面のMaterial IconsをLucide（`lucide_icons_flutter`）へ置き換える。同一画面でMaterialとLucideを混在させない。tooltip/semanticsは維持する | 軽量レーン | 出典: 2026-07-06人間裁定 / `docs/design/ui-spec.md` 裁定済み事項 |
| 8 | FTS5検索の配線 | `tasks_fts` の同期トリガー、またはアプリ層更新 + 検索API + （UIはPhase 3送り） | M1-02残課題 | task-02の完了報告「やらないこと」参照 |
| 9 | iOS Keychain DeviceKeyStore | 本番用DK保存。`FileDeviceKeyStore` を置き換える | M4 | セキュリティ上の必須事項 |
| 10 | ローカル通知 | F-24〜F-26。iOS先行で実装する | M4 | |
| 11 | 設定値の永続化機構とF-01 UIモード設定の保存口 | 設定値を永続化する仕組みを用意し、F-01のUIモード選択の保存口を実装する | M4 | 出典: Phase1計画書§1（F-01「設定値の保存口のみ用意」）。通知設定・UIモードの前提。2026-07-06親棚卸しで確認 |
| 12 | アクセシビリティ検証パス | Dynamic Type / スクリーンリーダーラベル / コントラストの確認項目を通す | M4-03 | |
| 13 | 性能検証 | 1万件データで起動2秒以内・主要操作60fps・オフライン動作を計測し、結果を記録する | M4-04 / F-50〜F-52 | |
| 14 | 日付・時刻表記のロケール準拠リファクタ | 固定パターン `DateFormat('EEE, MMM d')` 等をskeleton API（`yMMMEd`等）へ置換し、ホストのロケール設定に従う | M4系 | 出典: 2026-07-06人間指示（`docs/design/ui-spec.md`参照）。ja表示「月, 7月 6」の不自然さもこれで解消 |
| 15 | オンボーディング/初回起動体験 | 範囲設計のplannerタスクから開始する。DK復旧不可の注意表示（計画書§5リスク表）を含む。マスコットの利用はvisual-direction.mdの方針に従う | M4系 | 出典: 2026-07-06人間裁定（要人間判断→確定） |
| 16 | iOSリリースビルド/署名/ストア提出準備 | macOS環境でReleaseビルドが成功し、ストア提出前のコンプライアンス確認項目を整理する | M5-01 | |
| 17 | Phase 1リリース前にthemeModeをライト固定 | ダークモード正式対応まではアプリの`themeMode`をlight固定にする。dark系トークン・コードは残置し、priority dot固定hexのコントラスト検証等の磨き込みはダークモード対応再開時（裁定により直近スコープ外）に行う | M5系 | 出典: 2026-07-06人間裁定 |
| 18 | macOS dogfoodingビルド配布 | macOS desktopで主要操作が通り、既知差分をリリースノートに記録する | M5-02 | |
| 19 | クラッシュレポート方針の確定 | F-53オプトイン文言・PII除去対象・実送信するかの判断を記録する | M5-03 | |
| 20 | SQLCipherクロスビルドのiOS/Android CI検証 | iOS/AndroidのSQLCipherビルド差分をCIで継続検証する | Phase1計画書§6 | |

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

- タスク行右側affordanceの将来形（chevron継続か、Focus開始ボタンか）。出典: `docs/design/visual-direction.md` Focus Timer節 / `docs/design/ui-spec.md` セクション6。
- リストの型の区別（プロジェクト型=完了・アーカイブしうる大タスク / エリア型=継続する生活領域）の要否とUI上の使い分け。アーカイブ機能自体は2026-07-07人間裁定（削除モデル）によりPhase 1導入が確定済み（task-37）。型の区別づけはPhase 3検討。出典: 2026-07-07人間コメント（task-35削除セマンティクス検討時）。
