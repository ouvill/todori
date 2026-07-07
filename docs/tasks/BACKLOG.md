# docs/tasks/ バックログ

`docs/tasks/` 配下の作業指示書と完了報告から見える現在の進捗、および次に着手すべきタスクの優先度付きリストである。新しいタスクに着手する前に必ず参照すること。

## 現在地（2026-07-08時点）

- **Phase 1 / M1（コア層）: 完了。** task-05（`core/domain` ユースケース） / task-06（`core/storage` リポジトリ） / task-07（Device Key抽象）。
- **Phase 1 / M2（ブリッジとUI骨格）: 完了。** task-08（ブリッジAPI公開） / task-09（Riverpod + go_router 画面骨格） / task-10（i18n en/ja） / task-11（CI整備）。macOSデスクトップ実行はcargokitで確立済みで、Phase 1品質ゲートはGitHub Actionsへ追加済み。
- **Phase 1 / M3（機能完成）: 完了（2026-07-07）。** M3-01〜M3-05の完了条件を充足済み（M3-01はtask-35改名+task-38削除、M3-04はtask-39で完了。削除の意味論は2026-07-07仕様改訂ADR-009に基づく）。
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
- 2026-07-07人間裁定（データ保持原則）: 完了済みタスクはリスト削除で失われない。リスト整理の保全経路はアーカイブへ変更され、task-35（改名のみ）/task-36（マイグレーション機構）/task-37（リストアーカイブ）/task-38（恒久削除移行）に再編。
- 2026-07-07人間裁定（削除モデル: ゴミ箱廃止・恒久削除＋警告・削除Undoなし・完了/編集Undo維持・アーカイブPhase 1導入。docs/05 ADR-009 / docs/02 F-07・F-09改訂）
- **リスト名称変更UI合格済み**: task-35（リスト改名）は2026-07-07親レビューで合格済み。`flutter analyze` / `flutter test` / `cargo test` / `lists.png` 目視確認済み。
- **DBスキーママイグレーション機構合格済み**: task-36は migration runner と `lists.archived_at` v2 マイグレーションを実装し、2026-07-07親レビューで合格済み。`core/storage` テストは20件成功。
- **リストアーカイブUI合格済み**: task-37（リストのアーカイブ/アーカイブ解除）は2026-07-07親レビューで合格済み。
- **ゴミ箱廃止・恒久削除合格済み**: task-38は2026-07-07親レビューで合格済み。Flutter 47件、Rust全スイート、削除確認スクリーンショット確認済み。
- **wont_do / 再オープンUI合格済み**: task-39は2026-07-07親レビューで合格済み。Flutter 51件、Rust全スイート、`wont_do_row.png` スクリーンショット確認済み。
- **タスク一覧Closed挙動合格済み**: task-40（一覧チェック解除+サブタスクClosed同伴）は2026-07-07親レビューで合格済み。
- **リスト一覧純ナビ化合格済み**: task-41（リスト一覧純ナビ化+操作メニュー移設）は2026-07-07親レビューで合格済み。修正セッション1回で、メニュー影が黒枠に見える問題を `elevation: 0` により解消済み。
- **詳細画面インライン編集合格済み**: task-42（詳細インライン編集）は2026-07-07親レビューで合格済み。右上編集ボタンと一括編集ダイアログを撤去し、タイトル/ノート/期日/優先度を詳細画面上で直接編集できるようにした。Flutter 56件成功。
- **Design Lab準拠ビジュアル統一合格済み**: task-43（Design Lab準拠のタスク一覧ビジュアル整合）は2026-07-07親レビューで合格済み。Flutter 56件成功、Lab並列目視比較済み。
- **チェックボックストグル一貫性合格済み**: task-44（チェック常時トグル+Undo自動消滅）は2026-07-07親レビューで合格済み。Flutter 62件成功。
- **階層ガイド/詳細子孫ツリー合格済み**: task-45（階層ガイド├└+詳細子孫ツリー+編集がたつき解消）は2026-07-07親レビューで合格済み。Flutter 65件成功、3階層スクリーンショット確認済み。
- **既定Inbox自動プロビジョニング合格済み**: task-46（既定Inbox自動プロビジョニング+v3マイグレーション）は2026-07-07親レビューで合格済み。storage 28件、Flutter 65件成功。
- **Todayスマートビュー化合格済み**: task-47（Todayスマートビュー化+Lists画面Today導線）は2026-07-07親レビューで合格済み。Rust全13スイート、Flutter 70件成功、スクショ2枚目視確認済み。
- **Lucideアイコン統一完了**: task-48（Lucideアイコン統一）で本番UIのMaterial Iconsを `lucide_icons_flutter` へ置換し、Home / Lists / Task list / Task detail / タスク作成シートの混在を解消した。grepで `app/lib` の本番Material `Icons.` 残存ゼロを確認済み。
- **詳細画面3改善合格済み**: task-49（詳細画面の親リンク・全幅タップ・タイトル横チェック）は2026-07-07親レビューで合格済み。Flutter 75件成功。
- **D&D並び替え合格済み**: task-50（タスク一覧の手動並び替えD&D化）は2026-07-07親レビューで合格済み。Flutter 76件成功、同一親制約/semanticsテスト、ドラッグ中スクリーンショット確認済み。
- **Home改善サイクル第1回（2026-07-07）**: 3案画像生成（A: TickTick方向 / B: Todoist方向 / C: 現行構造polish）→人間選択（A案の構造×C案の行表現+横幅/トップ圧縮+Tomorrow/Upcoming追加）→task-51/52/53へ分割済み。
- **Homeセクション構造合格済み**: task-51（Home4セクション構造+セリフ日付見出し）は2026-07-07親レビューで合格済み。修正セッション1回で、見出しセリフ欠落を解消済み。
- **クイック追加バー合格済み**: task-52（下部常設クイック追加バー）は2026-07-07親レビューで合格済み。
- **スワイプ+モーション静的検証済み**: task-53（タスク行スワイプ+軽量モーション）は `flutter_slidable` / `flutter_animate` を導入し、2026-07-07親レビューで静的検証済み。**モーションの最終受け入れは人間ドッグフーディング待ち**。
- **Home改善サイクル第1回はコード完了。モーション体感の人間受け入れのみ残**。
- **2026-07-07ドッグフーディング第1回実施。** フィードバック5件はtask-40〜43で全件消化済み。
- **2026-07-07ドッグフーディング第2回実施。** フィードバック11件はtask-44〜47で全件消化済み。
- **2026-07-07ドッグフーディング第3回実施。** フィードバック4件はtask-49/50で全件消化済み。
- **タスク作成ボトムシート合格済み**: task-54（作成ボトムシート）は2026-07-08親レビューで合格済み。Flutter 84件成功、Labモック比較を目視確認済み。
- **Homeサブツリー同伴表示合格済み**: task-55（Homeサブツリー同伴）は2026-07-08親レビューで合格済み。Flutter 85件成功。修正セッション1回で、無情報ピル/件数/冗長ラベルの3指摘を解消済み。
- **チェックボックスpolish合格済み**: task-56（チェックボックスpolish）は2026-07-08親レビューで合格済み。チェックボックス整列/細線化/アニメを実装し、Flutter 85件成功、3階層整列スクショを確認済み。チェックアニメの体感受け入れはtask-53のモーションと合わせて人間ドッグフーディング待ち。
- **2026-07-08人間裁定（Home重複表示の解消）**: task-55の「子がより早いセクションに該当する場合は親配下と該当セクションの両方に表示」規則は、3階層それぞれに期日が付くケースで同一タスクが最大3回表示されノイズになるため廃止する。Homeは1タスク1表示、同伴サブツリー内の単独表示子孫剪定、サブタスク単独行の親ラベル表示へ改訂し、task-57として指示書化済み。
- **Home重複排除+親ラベル合格済み**: task-57（Home重複排除+親ラベル）は2026-07-08親レビューで合格済み。Flutter 85件成功、3階層×3期日シナリオのスクショ確認済み。
- **2026-07-08人間裁定（Home完了タスクの単独表示抑止）**: 完了済みなのに期日超過のサブサブタスクがOverdueへ単独表示されたままになるドッグフーディング指摘を受け、日付セクションへの単独表示は未完了タスクのみに限定する。完了タスクは表示中祖先があればその下へmuted + 取り消し線で同伴し、完了ルートはClosedへ、表示中祖先がない完了サブタスクはHome非表示とする。task-58として指示書化済み。
- **Home完了タスクの単独表示抑止合格済み**: task-58（完了タスクのセクション単独表示廃止・親ツリー同伴）は2026-07-08親レビューで合格済み。Flutter 88件成功、報告シナリオのスクショ確認済み。
- **2026-07-08ドッグフーディング第4回実施。** フィードバック2件（タスク追加をボトムシート化、Home表示親タスク配下へ期日なしサブタスクも同伴）はtask-54/55で全件消化済み。
- **2026-07-08ドッグフーディング第5回実施。** フィードバック3件（ツリー表示のチェック丸と縦線ずれ、チェック時の楽しさ、未チェック円線の太さ）はtask-56で全件消化済み。
- **2026-07-08ドッグフーディング第6回実施。** フィードバック2件（チェックボックス列の左寄せ、ツリー横棒の終端）は軽量レーンで消化済み。
- **2026-07-08軽量レーン消化済み。** 完了行の日付pill/メタデータをmuted化し、完了済みタスクが緊急色を持ち続けないようにした。
- **2026-07-08人間裁定（チェック完了モーション）。** Any.doの左から右へ伸びる取り消し線と、Xのハートに近いチェック起点の小パーティクルを参照し、チェックON時は「チェック線path描画 → チェック点から局所パーティクル → タイトル取り消し線の左から右への伸長」とする。celebration禁止は全廃せず、チェックボックス起点の局所的な小パーティクル（半径24px級・0.5秒級・ブランド色）だけを許容し、画面全体のconfetti、トロフィー、音、全画面演出は引き続き禁止する。
- **チェック完了モーションtask-59化済み。** task-59（チェック完了モーション）として、チェック線path描画、取り消し線伸長、局所パーティクル、Reduce Motion分岐、widget test、実装アニメーション一覧表を指示書化した。
- **チェック完了モーション合格済み**: task-59（チェック完了モーション）は2026-07-08親レビューで合格済み。チェック線path描画、取り消し線伸長、局所パーティクル、Reduce Motion対応を実装し、Flutter 90件成功、途中フレームスクリーンショット確認済み。体感の最終受け入れは人間ドッグフーディング待ち。
- **2026-07-08モーション体感受け入れFB。** チェック円とタップ領域/Ink波紋の中心ずれ、取り消し線アニメ終了フレームと静止状態の位置ずれ、Home単独表示行が完了モーション前に消える/移動する問題が見つかった。`docs/design/ui-spec.md` にチェック完了モーションの精度補足を追記し、task-60（チェック完了モーション受け入れFBの精度改善）として指示書化済み。
- **チェック完了モーション精度改善合格済み**: task-60（タップ同心化・取り消し線統一・完了遅延遷移）は2026-07-08親レビューで合格済み。Flutter 95件成功、endframe/staticスクショ一致確認済み。体感の最終受け入れは人間ドッグフーディング待ち。
- **2026-07-08 モーション体感の人間受け入れ完了。** 「完璧」評価により、task-53/56/59/60 と修正3回分を正式クローズ。Home改善サイクル第1回も完全クローズ。
- **日付・時刻表記のロケール準拠リファクタ完了**: task-61で固定/手組み日付整形をskeleton APIへ揃え、Home見出し・詳細Created at・期日表示のen/jaロケール追従をwidget testとvisual QAで確認済み。
- **2026-07-08 運用記録**: プロダクトオーナー長期離席のため、親エージェントが承認済みバックログの自律消化を開始（push なし・製品判断は要人間判断へ積む方針）。
- **2026-07-08 Phase 2自律実装承認**: プロダクトオーナーがPhase 1のリリース作業以外はPhase 2まで自律実装を進めてよいと承認した。Phase 2計画書 `docs/08_Phase2計画書.md` を作成し、E2EE同期・アカウント・マルチデバイスのマイルストーンをP2-M1〜P2-M5へ分解した。
- **2026-07-08 docs/03編集承認**: プロダクトオーナーが `docs/03_技術仕様書.md` の全面編集を許可した。変更時は外科的差分とし、日付・ADR参照注記を維持する。
- **FTS5検索の配線完了**: task-62で、v4マイグレーションによる `tasks_fts` 再構築・同期トリガー・storage/bridge検索API・英日検索テストを実装した。検索UIはPhase 3送りのまま。
- **設定値の永続化機構とF-01 UIモード保存口完了**: task-63で、v5マイグレーションによる `settings` テーブル、storage/bridge/Dart providerの設定読み書きAPI、`ui_mode` 既定値 `simple` helperを実装した。UIモード選択/切替UIはPhase 3送りのまま。
- **iOS/macOS Keychain DeviceKeyStore完了**: task-64で、Rust側からApple Security frameworkを呼ぶ方式、`AfterFirstUnlockThisDeviceOnly` 相当、既存 `device.key` からのデータロス回避移行、iOS Simulator/macOS dogfooding確認手順を実装・記録した。2026-07-08親レビュー合格。親ホストで実Keychain roundtrip ignoredテスト、macOS debugアプリの起動→再起動、鍵保持、DBオープン、login.keychain上の `dev.todori.todori.device-key` アイテム確認まで合格。iOS Simulator/実機の `flutter run` 通し確認は人間帰還後確認に残す。
- **ローカル通知task-65完了（2026-07-08）**: M4-01 / F-24・F-25対応として、`flutter_local_notifications` 採用、v6 `reminders`、bridge API、詳細画面リマインダーチップ、通知権限、スヌーズ最小版、起動時再スケジュール、完了/削除時キャンセル、Rust/Flutterテストと手動確認手順を実装した。
- **アクセシビリティ検証task-66完了（2026-07-08）**: M4-03対応として、タスク行/チェックボックス/チップ/シートのSemantics補強、Dynamic Type 2.0 visual QA、WCAG AAコントラスト計算、Reduce Motion確認、VoiceOver手動確認手順を記録した。コントラスト不足のcoral/amber/low priority dot/outline系は要人間判断として残した。
- **性能検証task-67完了（2026-07-08）**: M4-04 / F-50〜F-52対応として、1万件seedでRust storage起動近似・Home横断・単一リスト・検索・migration、Flutter大量pump、オフライン依存範囲を計測した。Rust起動近似は123ms、Flutter Home fake seed pumpは21秒台。Home大量構築は未解決事項として記録した。
- **task-67未解決事項の引き継ぎ**: Flutter Homeが7140件相当を初期構築してpump 21秒台になる問題をtask-68（Home/Tasksリスト描画の仮想化）として指示書化した。解消方針はHome/Tasksの `CustomScrollView` + Sliver遅延構築化であり、視覚・完了遅延遷移・チェックアニメ・スワイプ・D&D・階層ガイドを維持する。
- **Home/Tasksリスト描画の仮想化task-68完了（2026-07-08）**: Home/Tasksを `CustomScrollView` + Sliver遅延構築へ移行し、Home 7140件相当のFlutter pumpを21304msから630ms（単体性能test）/802ms（全体test内）へ短縮した。visual QA 43 PNGはbefore/after差分なし。
- **P2-M1 クライアント同期基盤task-69指示書化（2026-07-08）**: Phase 2最初の実装タスクとして、HLC、フィールドHLCマップ、LWWマージ、blob暗号エンベロープ、storage v8 outbox、proptest収束性検証を `docs/tasks/task-69-sync-foundation.md` に指示書化した。ステータスは未着手。サーバー・ネットワーク・Flutter UIはP2-M2以降へ分離する。
- **P2-M1 クライアント同期基盤task-69完了（2026-07-08）**: `core/sync` にHLC固定幅エンコード、field_hlcs、フィールドLWW、blob暗号エンベロープ、収束性proptest（64ケース）を追加し、`core/storage` v8でsync outboxとpull cursorを追加した。サーバー/ネットワーク/UI接続はP2-M2以降。

## 優先度付きバックログ

| # | タスク | 内容 | 対応マイルストーン | 備考 |
|---|---|---|---|---|
| 1 | task-68 Home/Tasksリスト描画の仮想化 | task-67で判明したHome 7140件相当の全行Widget構築を、Sliverベースの遅延構築へ移行する | M4-04 / F-51 | 完了（2026-07-08）。Home 21304ms→630ms、visual QA 43 PNG差分なし |
| 2 | task-65 ローカル通知 | F-24〜F-25。iOS先行でローカル通知、通知取消、スヌーズ最小版を実装する | M4-01 | 完了（2026-07-08）。E2EE設計上、通知はサーバーpushではなくローカル通知が正。`flutter_local_notifications` は人間の包括承認済み |
| 3 | task-66 アクセシビリティ検証パス | Dynamic Type / スクリーンリーダーラベル / コントラストの確認項目を通す | M4-03 | 完了（2026-07-08）。コントラスト不足の色判断は要人間判断に記録 |
| 4 | task-67 性能検証 | 1万件データで起動2秒以内・主要操作60fps・オフライン動作を計測し、結果を記録する | M4-04 / F-50〜F-52 | 完了（2026-07-08）。Rust起動近似123ms、Flutter Home fake seed pumpは21秒台 |
| 5 | Closedセクション見出しの冗長表記整理 | Closedセクション見出しが `"Closed 2 closed"` のように冗長表示される文言を整理する | Phase 1軽量レーン | 出典: 親レビュー2026-07-07 |
| 6 | オンボーディング/初回起動体験 | 範囲設計のplannerタスクから開始する。DK復旧不可の注意表示（計画書§5リスク表）を含む。マスコットの利用はvisual-direction.mdの方針に従う | M4系 | 出典: 2026-07-06人間裁定（要人間判断→確定） |
| 7 | 自然言語日付入力の解析 | クイック追加バー入力中の `tomorrow` / `next Friday` / `明日` 等を日付として解釈する | 将来枠 | 出典: 2026-07-07 Home裁定。task-52ではスコープ外 |
| 8 | SQLCipherクロスビルドのiOS/Android CI検証 | iOS/AndroidのSQLCipherビルド差分をCIで継続検証する | Phase1計画書§6 | |
| 9 | Phase 1リリース前にthemeModeをライト固定 | ダークモード正式対応まではアプリの`themeMode`をlight固定にする。dark系トークン・コードは残置し、priority dot固定hexのコントラスト検証等の磨き込みはダークモード対応再開時（裁定により直近スコープ外）に行う | M5系 | 出典: 2026-07-06人間裁定 |
| 10 | iOSリリースビルド/署名/ストア提出準備 | macOS環境でReleaseビルドが成功し、ストア提出前のコンプライアンス確認項目を整理する | M5-01 | 人間帰還後。署名・証明書・ストア提出判断が必要 |
| 11 | macOS dogfoodingビルド配布 | macOS desktopで主要操作が通り、既知差分をリリースノートに記録する | M5-02 | 人間帰還後。配布判断が必要 |
| 12 | クラッシュレポート方針の確定 | F-53オプトイン文言・PII除去対象・実送信するかの判断を記録する | M5-03 | 人間帰還後。法務/プライバシー判断が必要 |
| 13 | task-69 P2-M1 クライアント同期基盤 | HLC実装、フィールドHLCマップ、LWWマージ、outboxテーブル、blob暗号エンベロープ、proptestによる収束性テストを実装する | P2-M1 | 完了（2026-07-08）。指示書: [`task-69-sync-foundation.md`](./task-69-sync-foundation.md)。出典: `docs/08_Phase2計画書.md`、`docs/03` §4.8、§6.3、§6.4、§11.1 |
| 14 | P2-M2 サーバー実装 | Postgresスキーマ、OPAQUE登録/ログイン、push/pull、seq採番、§6.6不変条件、リポジトリ内完結のPostgresテスト環境を実装する | P2-M2 | 出典: `docs/08_Phase2計画書.md`。`docs/03` §1.5、§6.1、§6.2、§6.6、§7 |
| 15 | P2-M3 鍵階層とアカウント接続 | MK生成、exportKeyラップ、DEK、デバイス登録、Flutter最小アカウント画面、セッション管理を接続する | P2-M3 | 出典: `docs/08_Phase2計画書.md`。`docs/03` §4、§7 |
| 16 | P2-M4 同期エンジン統合 | クライアント同期ループ、push/pull/再push規約、競合マージのFlutter反映、オフライン耐性を実装する | P2-M4 | 出典: `docs/08_Phase2計画書.md`。`docs/03` §6.4、§6.5 |
| 17 | P2-M5 削除同期とマルチプラットフォーム検証 | ADR-010ドラフト、保守的な削除同期実装、Android/macOSビルド・動作検証を行う | P2-M5 | 出典: `docs/08_Phase2計画書.md`。ADR-010は人間レビュー待ちを明記 |

（`docs/07_Phase1計画書.md` のマイルストーン表と整合させること。表のID対応が計画書と厳密一致しない場合は「相当」と表記する。）

## 新タスク着手の手順

1. このBACKLOGと `docs/07_Phase1計画書.md` / `docs/08_Phase2計画書.md` を突き合わせて次に着手するタスクを選ぶ。
2. `docs/tasks/task-NN-<slug>.md` を、既存タスク（task-05〜10が良い見本）と同じ体裁で書く: 1. 背景とコンテキスト、2. 事前に読むべきファイル、3. ゴール、4. スコープ（やること/やらないこと）、5. 実装手順（例）、6. 受け入れ基準（チェックボックス）、7. 制約・注意事項、8. 完了報告に含めるべき内容。あわせて `docs/tasks/README.md` のタスク一覧表に行を追加する。
3. 指示書をコミットしてから実装に着手する。
4. 品質ゲートを全通過させる → 指示書に「## 9. 完了報告」を追記する → Conventional Commitsでコミットする。
5. 完了後、このBACKLOG.mdの「現在地」セクションを更新する。

## 補充のルール

- このバックログは自動では増えない。PLAYBOOK.md のセッション種別6（バックログ補充）を定期的に実行して棚卸しする
- タスクの供給源は3つに限る: (1) docs/07_Phase1計画書 / docs/08_Phase2計画書のマイルストーン表 (2) 各タスク完了報告の未解決事項 (3) 計画書のリスク表。**出典のないタスクを積んではならない**
- 仕様の追加・変更を伴うものはバックログに直接入れず「要人間判断」に置く

## 要人間判断

- iOS Simulator/実機でのKeychain動作通し確認。task-64は親ホストの実Keychain roundtripとmacOS debugアプリ再起動確認まで合格済みだが、iOS Simulator/実機での `flutter run`、アプリ終了/再起動、Keychain鍵保持、SQLCipher DB再オープンは人間帰還後に確認する。出典: task-64完了報告。
- ADR-010（削除同期表現）の承認。ADR-009後のローカル恒久削除と、Phase 2同期上のtombstone/GC/復帰端末の扱いを最終決定する。出典: `docs/08_Phase2計画書.md` P2-M5。
- AWS/ECR/Lambda/Neon本番デプロイ実行。クレデンシャル投入、WAF/API GatewayまたはCloudFront前段、実環境の更新は人間帰還後に行う。出典: `docs/08_Phase2計画書.md` §2、§6。
- タスク行右側affordanceの将来形（chevron継続か、Focus開始ボタンか）。出典: `docs/design/visual-direction.md` Focus Timer節 / `docs/design/ui-spec.md` セクション6。
- リストの型の区別（プロジェクト型=完了・アーカイブしうる大タスク / エリア型=継続する生活領域）の要否とUI上の使い分け。アーカイブ機能自体は2026-07-07人間裁定（削除モデル）によりPhase 1導入が確定済み（task-37）。型の区別づけはPhase 3検討。出典: 2026-07-07人間コメント（task-35削除セマンティクス検討時）。
