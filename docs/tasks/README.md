# docs/tasks/ ── 外部AIエージェント向け作業指示書

このディレクトリは、E2EE Todoアプリ「Todori」の実装作業を外部のAIコーディングエージェントに委託するための**作業指示書**を置く場所である。各指示書はリポジトリの事前知識がないAIエージェントが単独で読み、単独で完遂できることを目標に書かれている。

実行エージェントは作業前にリポジトリルートの `AGENTS.md` も読むこと。

## 前提ドキュメント

作業前に必ず以下を読むこと（各指示書内でも該当箇所を指示する）。

- [`docs/01_企画書.md`](../01_企画書.md) ── プロダクト企画・ロードマップ
- [`docs/02_機能仕様書.md`](../02_機能仕様書.md) ── 機能仕様（F-01〜F-53）
- [`docs/03_技術仕様書.md`](../03_技術仕様書.md) ── 技術仕様（本リポジトリの技術的な唯一の真実源）
- [`docs/billing_overview.md`](../billing_overview.md) ── 公開版の課金方針（Phase 1では不要なことが多い）
- リポジトリルートの [`README.md`](../../README.md) ── monorepo構成の概要

## タスク一覧

| ID | ステータス | ファイル | 概要 | 依存関係 |
|---|---|---|---|---|
| task-01 | 完了 | [task-01-opaque-poc.md](./task-01-opaque-poc.md) | OPAQUE認証PoC。`core/crypto` に opaque-ke を統合し、登録→ログイン→exportKey→KEK導出→Master Keyラップの一気通貫動作を実証する | 雛形（現在のリポジトリ状態）にのみ依存。task-02と並行実施可 |
| task-02 | 完了 | [task-02-sqlcipher-poc.md](./task-02-sqlcipher-poc.md) | SQLCipherビルド検証。`core/storage` に rusqlite(SQLCipher) を導入し、暗号化DBの動作・Androidクロスビルド可否を検証する | 雛形にのみ依存。task-01と並行実施可 |
| task-03 | 完了 | [task-03-flutter-rust-bridge.md](./task-03-flutter-rust-bridge.md) | flutter_rust_bridge統合。`app/` から Rust コアを呼び出す最小の垂直貫通を確立する | 雛形（`core/domain` 等）にのみ依存。task-01/02の結果は不要 |
| task-04 | 完了 | [task-04-phase1-plan.md](./task-04-phase1-plan.md) | Phase 1（MVP）計画書 `docs/07_Phase1計画書.md` の作成。ドキュメント作業のみでコード変更なし | 雛形にのみ依存。他タスクと並行実施可。ただし計画書内でtask-01〜03のPoC結果を前提とする箇所がある旨を明記する |
| task-05 | 完了 | [task-05-domain-usecases.md](./task-05-domain-usecases.md) | `core/domain` にリスト/タスク操作ユースケース（生成・編集・ステータス遷移・論理削除/復元・サブタスク制約検証）を追加する | 雛形にのみ依存。単独実施可。Phase1計画書M1-01に対応 |
| task-06 | 完了 | [task-06-storage-repositories.md](./task-06-storage-repositories.md) | `core/storage` に `lists` テーブルを追加し、`ListRepository` / `TaskRepository::update` を実装して `core/domain` のユースケースと接続する | task-02・task-05の成果物に依存。Phase1計画書M1-02/M1-03に対応 |
| task-07 | 完了 | [task-07-device-key.md](./task-07-device-key.md) | `core/crypto` にDevice Key生成・OSキーチェーン抽象（trait）・SQLCipher用ローカルDB鍵導出を実装し、`core/storage` でDK生成からDB openまでの統合テストを実証する | task-02・task-06の成果物に依存。Phase1計画書M1-04に対応 |
| task-08 | 完了 | [task-08-bridge-usecases.md](./task-08-bridge-usecases.md) | `todori-app-bridge` にリスト/タスク操作のユースケース単位APIを公開し、Dartテストからリスト作成・タスク作成・取得ができることを実証する | task-03・task-05〜07の成果物に依存。Phase1計画書M2-02に対応 |
| task-09 | 完了 | [task-09-ui-skeleton.md](./task-09-ui-skeleton.md) | Flutterの画面遷移骨格（リスト一覧→タスク一覧→タスク詳細）と状態管理（Riverpod）方針を実装する | task-08の成果物に依存。Phase1計画書M2-03に対応 |
| task-10 | 完了 | [task-10-i18n.md](./task-10-i18n.md) | i18n基盤（en/ja ARB）を導入し、画面骨格のUI文字列を外部化してシステム言語に追従させる | task-09の成果物に依存。Phase1計画書M2-04に対応 |
| task-11 | 完了 | [task-11-ci.md](./task-11-ci.md) | GitHub ActionsでRust/Flutter品質ゲート、FRB再生成差分チェック、直書き検出を自動化する | task-08〜10の成果物に依存。Phase1計画書M2-01に対応 |
| task-12 | 完了 | [task-12-open-source-readiness.md](./task-12-open-source-readiness.md) | OSS公開前監査。秘密情報、公開不適切情報、OSS基本文書、ライセンス、public repo向けCI/Actions安全性を棚卸しする | task-11までの成果物に依存。public repository化の事前確認 |
| task-13 | 完了 | [task-13-public-private-docs-split.md](./task-13-public-private-docs-split.md) | public repoを主、private repoを非公開資料側とする運用に向け、公開/非公開ドキュメント分類と移行計画を策定する | task-12の監査結果に依存。public repository化の事前確認 |
| task-14 | 完了 | [task-14-public-private-repo-split.md](./task-14-public-private-repo-split.md) | public/privateのsibling repo運用に向け、公開版の課金・法務要約、READMEリンク整理、private退避マッピングを作成する | task-13の分割方針に依存。private repo名は `todori-private`。GitHub public visibilityは人間作業で有効化済み |
| task-15 | 完了 | [task-15-security-policy.md](./task-15-security-policy.md) | public化前に `SECURITY.md` を作成し、脆弱性報告導線とGitHub private vulnerability reporting利用方針を整備する | task-12の監査結果に依存。GitHub private vulnerability reportingは人間作業で有効化済み |
| task-16 | 完了 | [task-16-flutter-analyze-build-artifact.md](./task-16-flutter-analyze-build-artifact.md) | `flutter analyze` がmacOS build artifact内の古いcargokit参照で失敗する原因を調査し、品質ゲートを復旧する | task-14検証セッションで発見。機能変更ではなく品質ゲート復旧 |
| task-17 | 完了 | [task-17-ios-simulator-flutter-run.md](./task-17-ios-simulator-flutter-run.md) | iOS Simulatorで `flutter run` を実行し、Cargokit / CocoaPods / Xcode / FRB / SQLCipher のアプリ起動パイプラインを検証する | task-08〜11・task-16の成果物に依存。M2残のiOSビルド組み込み検証 |
| task-18 | 完了 | [task-18-task-editing-ui.md](./task-18-task-editing-ui.md) | タスク詳細画面で `title` / `note` / `priority` / `due_at` を編集し、ブリッジ更新API経由でDBへ反映する | task-08〜10の成果物に依存。M3-02のタスク編集部分 |
| task-19 | 完了 | [task-19-subtasks-ui.md](./task-19-subtasks-ui.md) | サブタスク表示・作成。`validate_parent` / `validate_parent_for` を使うブリッジ公開と、階層表示・進捗表示・親完了確認UIを実装する | task-08〜10・task-18の成果物に依存。M3-03相当 |
| task-20 | 完了 | [task-20-ui-foundation.md](./task-20-ui-foundation.md) | task-18/19後のUI文法を整える。ThemeData、共通task row/metadata、空状態、ダイアログ、既存Lists/Tasks/TaskDetailの見た目を小さく整理する | task-18・task-19の成果物に依存。ゴミ箱画面・復元UI、並び替え、通知へ進む前のUI基盤整備 |
| task-21 | 完了 | [task-21-visual-direction.md](./task-21-visual-direction.md) | 参考画像 `assets/brand/generated/todori-mobile-product.png` の方向性を、既存UI foundationへ実アプリの視覚文法として反映する | task-20の成果物に依存。ゴミ箱画面・復元UI、並び替え、通知へ進む前の視覚方向性反映 |
| task-22 | 完了 | [task-22-design-direction-sketch.md](./task-22-design-direction-sketch.md) | 「柔らかく・親しみやすく・エレガント」を主要画面の画像モックと `docs/design/visual-direction.md` のデザインルールへ具体化する | task-20・task-21の成果物に依存。ゴミ箱画面・復元UI、並び替え、通知へ進む前のデザイン正本作成 |
| task-23 | 完了 | [task-23-trash-restore-ui.md](./task-23-trash-restore-ui.md) | ゴミ箱画面・復元UI。既存の `get_trashed_tasks` / `restore_task` / `trash_task` を使い、削除済みタスク一覧と復元導線を追加する | task-18〜22の成果物に依存。BACKLOG上はM3-04相当、計画書上はM3-02の削除/復元残りにも対応 |
| task-24 | 完了 | [task-24-fractional-index.md](./task-24-fractional-index.md) | fractional index生成の本実装と、タスク一覧の同一階層内手動並び替えUIを追加する | task-18〜23の成果物に依存。M3-05のうちUndoと条件ソートUIは後続タスクへ分離 |
| task-25 | 完了 | [task-25-design-calibration-ui-pass.md](./task-25-design-calibration-ui-pass.md) | design calibration UI pass。AI生成画像・画像モックへのピクセル追従ではなく、既存実画面の密度、操作性、i18n、アクセシビリティを小さく較正する | task-20〜24と `docs/design/visual-direction.md` に依存。Undo・条件ソートUIへ進む前のUI実装判断の較正 |
| task-26 | 完了 | [task-26-undo.md](./task-26-undo.md) | 削除/完了/編集のUndo。履歴データ構造、操作単位、復元時の競合方針を定めて実装する | task-18〜25の成果物に依存。M3-05のうち条件ソートUIは後続タスクへ分離 |
| task-27 | 完了 | [task-27-condition-sort-ui.md](./task-27-condition-sort-ui.md) | 条件ソートUI。Tasks画面で手動順 / 締切 / 優先度 / 作成順の表示順切替を追加する | task-24〜26の成果物に依存。M3-05の残り |
| task-28 | 完了 | [task-28-visual-polish.md](./task-28-visual-polish.md) | Visual polish / product UI refinement。Lists / Tasks / Detail / Trash / Dialog / Empty state を、実データで破綻しないままApp Store/READMEスクリーンショット前の第一印象としてプロダクト品質へ引き上げる | task-20〜27と `docs/design/visual-direction.md` に依存。M3 polish |
| task-29 | 完了 | [task-29-product-experience-alignment.md](./task-29-product-experience-alignment.md) | Product experience alignment。起動直後をListsではなく既定リストのTasks体験へ寄せ、指定2枚のdesign directionに近いtask-first UIへ組み替える | task-20〜28と `docs/design/visual-direction.md` に依存。M3 polish follow-up |
| task-30 | 完了 | [task-30-design-mood-alignment.md](./task-30-design-mood-alignment.md) | design mood alignment。ブランドタイポグラフィ(Lora/Inter)導入、タスク行メタデータのquieting、行密度圧縮、detail画面のLocal protectionチップ削除で参照画像の雰囲気へ寄せる | task-28/29と `docs/design/visual-direction.md`、visual QAスクショ基盤に依存。M3 polish follow-up |
| task-31 | 完了 | [task-31-trash-visual-refinement.md](./task-31-trash-visual-refinement.md) | Trash visual refinement。Trash行の日付・priority表現をtask-30後の文法へ揃え、visual QA seedとダークテーマpriority dot検証を整える | task-23・task-30と `docs/design/visual-direction.md`、visual QAスクショ基盤に依存。M3 polish follow-up |
| task-32 | 完了 | [task-32-task-list-interaction-refinement.md](./task-32-task-list-interaction-refinement.md) | Task list interaction refinement。リスト画面の左方向遷移、Completed折りたたみ、サブタスク進捗バッジ非表示、priority dot中央揃えを行う | task-30〜31と `docs/design/visual-direction.md`、visual QAスクショ基盤に依存。M3 polish follow-up |
| task-33 | 完了 | [task-33-flutter-design-lab.md](./task-33-flutter-design-lab.md) | Flutter Design Lab。visual QA上で本番UIを壊さずにToday/Task体験の複数モックをPNG比較できる実験場を作る | task-28〜32と `docs/design/visual-direction.md`、visual QAスクショ基盤に依存。M3 polish follow-up |
| task-34 | 完了 | [task-34-typography-rollout.md](./task-34-typography-rollout.md) | typography rollout。2026-07-06タイポ裁定（Newsreader範囲制限＋システム和文セリフ、Lora退役）を本番へ反映する | task-30・task-33の成果物と`docs/design/ui-spec.md`裁定済み事項に依存。M3 polish follow-up |
| task-35 | 完了 | [task-35-list-rename.md](./task-35-list-rename.md) | リスト名称変更。domain→storage→bridge→Dart→UIの縦貫通で、M3-01完了条件の残りのうち名称変更のみを実装する（削除モデルは2026-07-07人間裁定によりtask-37アーカイブ/task-38恒久削除へ再編） | task-08〜10の成果物に依存。BACKLOG優先度付きバックログ#1 |
| task-36 | 完了 | [task-36-schema-migration.md](./task-36-schema-migration.md) | DBスキーママイグレーション機構。`core/storage` に `PRAGMA user_version` ベースのバージョニングとマイグレーションランナーを整備し、v2で `lists.archived_at` を追加する | task-35の完了状態に依存。task-37（リストのアーカイブ/解除）の前提 |
| task-37 | 完了 | [task-37-list-archive.md](./task-37-list-archive.md) | リストのアーカイブ/アーカイブ解除。F-09改訂・ADR-009に準拠し、完了履歴を保全したまま通常一覧から分離する | task-36の完了状態に依存。task-38（ゴミ箱廃止と恒久削除移行）の前提 |
| task-38 | 完了 | [task-38-trash-removal.md](./task-38-trash-removal.md) | ゴミ箱廃止と恒久削除への移行。trash UI/route/APIを撤去し、タスク・リスト削除を物理DELETE＋不可逆警告の追加確認へ移行する | task-37（リストのアーカイブ/解除）の完了状態に依存。ADR-009 / F-07改訂 / docs/03改訂準拠 |
| task-39 | 完了 | [task-39-wont-do-reopen.md](./task-39-wont-do-reopen.md) | `wont_do`（やらないことにする）と再オープンをUIから実行できるようにし、F-06のステータス遷移を画面上に配線する | task-38の完了状態に依存。M3-04完了条件の残り |
| task-40 | 完了 | [task-40-task-list-behavior.md](./task-40-task-list-behavior.md) | タスク一覧でClosed行の先頭コントロールから再オープンできるようにし、閉じたサブタスクを親の下に残す | task-39の完了状態に依存。2026-07-07ドッグフーディング項目2・3。2026-07-07親レビュー合格 |
| task-41 | 完了 | [task-41-list-nav-simplify.md](./task-41-list-nav-simplify.md) | リスト一覧行を純粋なナビゲーション行へ単純化し、リスト操作を開いたリスト画面右上overflowへ移設する | task-38の完了状態に依存。2026-07-07ドッグフーディング項目1。2026-07-07親レビュー合格 |
| task-42 | 完了 | [task-42-detail-inline-edit.md](./task-42-detail-inline-edit.md) | 詳細画面の右上編集ボタンと一括編集ダイアログを撤去し、タイトル/ノート/期日/優先度を詳細画面上で直接編集できるようにする | task-18・task-26・task-40・task-41の完了状態に依存。2026-07-07ドッグフーディング項目4。2026-07-07親レビュー合格 |
| task-43 | 完了 | [task-43-lab-visual-alignment.md](./task-43-lab-visual-alignment.md) | Design LabのToday/タスク一覧構造へ本番を寄せ、Tasks単一パネル化、priority dotメタデータ行移動、chevron撤去、下中央Add task pill、Closed/Archived/チップ高さの既知nitsを整える | task-42の完了状態に依存。2026-07-07親レビューのDesign Lab比較ギャップ分析 |
| task-44 | 完了 | [task-44-checkbox-toggle-consistency.md](./task-44-checkbox-toggle-consistency.md) | チェックボックスを一覧・ネスト行・詳細画面Subtasks・アーカイブ済みリスト内で常時トグル化し、Undoスナックバーを4秒自動消滅へ揃える | task-43の完了状態に依存。2026-07-07ドッグフーディング第2回。2026-07-07親レビュー合格 |
| task-45 | 完了 | [task-45-tree-guides-and-detail.md](./task-45-tree-guides-and-detail.md) | 階層ガイドのL字/T字描画、詳細画面Subtasksの子孫ツリー表示、タイトル/ノート編集開始時のがたつき解消を行う | task-43の完了状態に依存。2026-07-07ドッグフーディング第2回。2026-07-07親レビュー合格 |
| task-46 | 完了 | [task-46-default-inbox.md](./task-46-default-inbox.md) | 既定Inboxの自動プロビジョニングと永続識別。v3マイグレーションで `lists.is_default` を追加し、sort_order先頭ルールを置き換える | task-36〜45の完了状態に依存。2026-07-07ドッグフーディング第2回。2026-07-07親レビュー合格 |
| task-47 | 完了 | [task-47-today-smart-list.md](./task-47-today-smart-list.md) | Todayスマートリスト化。Todayを全リスト横断（アーカイブ済みリスト除外）の期日今日+期日超過ビューへ移行し、Add taskは既定Inboxへ今日期日で作成する | task-46の完了状態に依存。2026-07-07ドッグフーディング第2回。2026-07-07親レビュー合格 |
| task-48 | 完了 | [task-48-lucide-icons.md](./task-48-lucide-icons.md) | Lucideアイコン統一。本番UIのMaterial Iconsを `lucide_icons_flutter` へ置換し、tooltip/semanticsを維持したまま画面内混在を解消する | task-43〜47の完了状態に依存。2026-07-06人間裁定 |
| task-49 | 完了 | [task-49-detail-refinements.md](./task-49-detail-refinements.md) | 詳細画面の親リンク・全幅タップ・タイトル横チェック。サブタスク詳細の親文脈、タイトル/ノート編集起動領域、詳細上の完了操作を改善する | task-44〜47の完了状態に依存。2026-07-07ドッグフーディング第3回 |
| task-50 | 完了 | [task-50-drag-drop-reorder.md](./task-50-drag-drop-reorder.md) | タスク一覧の手動並び替えを上下ボタンから長押しドラッグ&ドロップへ置換する。同一親内のみ許可し、reorder semanticsを維持する | task-24・task-43〜47の完了状態に依存。2026-07-07ドッグフーディング第3回 |
| task-51 | 完了 | [task-51-home-restructure.md](./task-51-home-restructure.md) | Home画面のセクション再構成。ルートをHomeへ再定義し、Overdue / Today / Tomorrow / Upcoming、圧縮ヘッダー、行再スタイル、Lists画面Homeリンク改名を行う | task-47・task-50の完了状態に依存。2026-07-07 Home改善サイクル第1回 |
| task-52 | 完了 | [task-52-quick-add-bar.md](./task-52-quick-add-bar.md) | 下部常設クイック追加バー。既存Add task pill/FAB+入力ダイアログを置換し、HomeではInbox+今日期日、通常リストではそのリスト+期日なしで即作成する | task-51の完了状態に依存。2026-07-07 Home改善サイクル第1回 |
| task-53 | 完了 | [task-53-swipe-and-motion.md](./task-53-swipe-and-motion.md) | タスク行スワイプと軽量モーション。`flutter_slidable` / `flutter_animate` を追加し、leading=完了、trailing=期日変更、150〜250ms級モーションを実装する | task-51・task-52の完了状態に依存。依存追加は2026-07-07人間承認済み |
| task-54 | 完了 | [task-54-create-task-sheet.md](./task-54-create-task-sheet.md) | 下部クイック追加バーをタスク作成ボトムシートのトリガーへ変更し、タイトル/Note/List/Due/Add taskをLabモック準拠で実装する | task-52・task-53の完了状態に依存。出典: ドッグフーディング2026-07-08#4 |
| task-55 | 完了 | [task-55-home-subtree-nesting.md](./task-55-home-subtree-nesting.md) | Home各セクションで、表示対象ルートタスクの配下サブツリー全体（期日なしサブタスク含む）を階層ガイド付きで表示する | task-45・task-51・task-53の完了状態に依存。出典: ドッグフーディング2026-07-08#4 |
| task-56 | 完了 | [task-56-checkbox-polish.md](./task-56-checkbox-polish.md) | チェックボックスpolish。階層ガイドの幾何、未チェックリングの細さ/色、チェックON/OFFマイクロモーションを整える | task-45・task-49・task-53・task-55の完了状態に依存。出典: ドッグフーディング2026-07-08#5 |
| task-57 | 完了 | [task-57-home-dedupe.md](./task-57-home-dedupe.md) | Home重複表示の解消。1タスク1表示、同伴サブツリー剪定、サブタスク単独行の親ラベル表示を実装する | task-55・task-56の完了状態に依存。出典: 2026-07-08人間裁定（Home重複表示の解消） |
| task-58 | 完了 | [task-58-home-closed-nesting.md](./task-58-home-closed-nesting.md) | Home完了タスクの単独表示抑止。完了した期日あり子孫を日付セクションへ単独表示せず、表示中祖先配下の同伴/完了ルートのClosed/祖先非表示サブタスクの非表示へ整理する | task-57の完了状態に依存。出典: 2026-07-08ドッグフーディング（完了済み期日超過サブサブタスクのOverdue残留） |
| task-59 | 完了 | [task-59-check-completion-motion.md](./task-59-check-completion-motion.md) | チェック完了モーション。チェック線path描画、左から右へ伸びる取り消し線、チェック起点の局所パーティクル、Reduce Motion分岐を実装する | task-56の完了状態に依存。出典: 2026-07-08人間裁定（チェック完了モーション） |
| task-60 | 完了 | [task-60-motion-refinement.md](./task-60-motion-refinement.md) | チェック完了モーション受け入れFBの精度改善。チェック円/ヒット領域/Ink同心化、取り消し線描画統一、Home単独表示行の完了後遅延退場を行う | task-59の完了状態に依存。出典: 2026-07-08モーション体感受け入れFB |
| task-61 | 完了 | [task-61-locale-date-format.md](./task-61-locale-date-format.md) | 日付・時刻表記のロケール準拠リファクタ。固定/手組み日付整形をskeleton APIへ揃え、Home見出し・Created at・期日表示の英日自然表記を検証する | task-60までの完了状態に依存。出典: 2026-07-06人間指示（`docs/design/ui-spec.md`） |
| task-62 | 完了 | [task-62-fts5-wiring.md](./task-62-fts5-wiring.md) | FTS5全文検索の配線。v4マイグレーションで `tasks_fts` 同期トリガー、storage/bridge検索API、英日検索テストを実装する | task-02・task-36の成果物に依存。M1-02残課題 / BACKLOG上位 |
| task-63 | 完了 | [task-63-settings-store.md](./task-63-settings-store.md) | 設定値の永続化機構とF-01 UIモード保存口。v5マイグレーションで `settings` を追加し、storage/bridge/Dart providerから `ui_mode` を読み書きできるようにする | task-36・task-62の完了状態に依存。Phase1計画書§1 / BACKLOG上位 |
| task-64 | 完了 | [task-64-keychain-device-key.md](./task-64-keychain-device-key.md) | iOS/macOS Keychain DeviceKeyStore。Rust側からApple Security frameworkを呼び、`FileDeviceKeyStore` から本番用Keychain保存へ移行する | task-07・task-08・task-17の成果物に依存。M4-02セキュリティ必須項目 / 2026-07-08親レビュー合格 |
| task-65 | 完了 | [task-65-local-notifications.md](./task-65-local-notifications.md) | ローカル通知。`flutter_local_notifications` を導入し、リマインダー保存、通知スケジュール、キャンセル、スヌーズ最小版をiOS/macOS先行で実装する | task-18・task-36・task-48・task-63・task-64の完了状態に依存。M4-01 / F-24・F-25 |
| task-66 | 完了 | [task-66-a11y-pass.md](./task-66-a11y-pass.md) | アクセシビリティ検証パス。Dynamic Type 2.0、スクリーンリーダーラベル、Tooltip/Semantics棚卸し、コントラスト計算、Reduce Motion確認を行う | task-48・task-54・task-60・task-65の完了状態に依存。M4-03 |
| task-67 | 完了 | [task-67-performance-verification.md](./task-67-performance-verification.md) | 性能検証。1万件seedでRust層起動近似・Home横断・単一リスト・検索・migration、Flutter大量pump、オフライン動作を計測する | task-66までの完了状態に依存。M4-04 / F-50〜F-52 |
| task-68 | 完了 | [task-68-home-virtualization.md](./task-68-home-virtualization.md) | Home/Tasksリスト描画の仮想化。task-67で判明したHome 7140件相当の全行Widget構築をSliver遅延構築へ移行する | task-67の完了状態に依存。task-67未解決事項の引き継ぎ |
| task-69 | 完了 | [task-69-sync-foundation.md](./task-69-sync-foundation.md) | P2-M1 クライアント同期基盤。HLC、フィールドHLCマップ、LWWマージ、blob暗号エンベロープ、storage v8 outbox、proptest収束性検証を実装する | `docs/08_Phase2計画書.md` P2-M1、`docs/03_技術仕様書.md` §4・§5・§6・§11.1、ADR-005に依存。サーバー/ネットワーク/UIはスコープ外 |
| task-70 | 完了 | [task-70-sync-server.md](./task-70-sync-server.md) | P2-M2 同期サーバー。Postgres/sqlx schema、OPAQUE登録/ログイン、セッション、push/pull、tenant_seq採番、§6.6不変条件、testcontainers Postgres統合テストを実装する | task-01・task-69の成果物、`docs/08_Phase2計画書.md` P2-M2、`docs/03_技術仕様書.md` §1.5・§2・§3・§6、ADR-003/005/008に依存 |

依存関係の要点: **task-01・task-02・task-03・task-04は互いに独立しており並行着手できる。** 各タスクは現在コミット済みの雛形（Rust workspace: `core/{domain,crypto,sync,storage}`, `cli`, `mcp-server`, `server` + Flutter `app/`）にのみ依存し、他タスクの成果物を前提としない。task-04（計画書）は内容としてtask-01〜03のPoC結果を参照する記述を含むが、計画書自体の執筆はPoCの完了を待たずに着手してよい（未完了の場合は「前提: task-0Xの結果待ち」と明記すること）。

## 共通規約

1. **作業前に仕様書を読む**: 各指示書が指定する `docs/01〜04` の該当箇所を必ず読み、リポジトリの設計思想と矛盾しない実装を行うこと。
2. **品質ゲート**: 以下がすべて通過することをコミット前に確認する。
   - `cargo fmt --all -- --check`
   - `cargo clippy --workspace -- -D warnings`
   - `cargo test --workspace`
   - Flutter（`app/`）に変更を加えた場合は追加で `cd app && flutter analyze` も通過すること
3. **コミット規約**: [Conventional Commits](https://www.conventionalcommits.org/)（`feat:` / `fix:` / `docs:` / `chore:` 等）に従う。コミット本文は日本語で構わない。1タスクにつき1〜数コミットを目安とする。
4. **変更禁止事項**:
   - `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の内容は変更しない。実装中にこれらの記述と矛盾する事実（ビルド不能、API仕様の相違等）を発見した場合は、**仕様書を書き換えずに**完了報告の「未解決事項」として報告すること。
   - `.github/workflows` 配下は、当該タスクの指示書に明記がある場合を除き変更しない。
5. **依存追加の作法**: Rustの依存クレートを追加する場合は、必ずリポジトリルート `Cargo.toml` の `[workspace.dependencies]` にバージョンを集約し、各crateの `Cargo.toml` からは `foo.workspace = true` の形で参照すること（既存の `core/crypto/Cargo.toml` 等の記法に倣う）。
6. **不明点・仕様の矛盾**: 推測で進めず、判明した時点で完了報告の「未解決事項」セクションに記録し、実装は指示書のスコープ内で合理的な暫定解を取ってよい（暫定解の内容も報告すること）。

## 共通受け入れ基準

全タスクに共通する受け入れ基準を以下に集約する。**各指示書はこのセクションを1行で参照し、タスク固有の受け入れ基準だけを書く（目安10項目以内）。** 共通項目を指示書へコピペしない（ボイラープレートが増えるほどworkerの注意がタスク固有の本質から薄まるため）。

- [ ] `cargo fmt --all -- --check` / `cargo clippy --workspace -- -D warnings` / `cargo test --workspace` が成功している
- [ ] `cd app && flutter analyze` が成功している（Flutter変更時）
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後 `cd app && flutter test` が成功している（Flutter変更時）
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している（Flutter変更時）
- [ ] `git diff --check` が成功している
- [ ] UI文字列はen/ja ARB化され、ARB変更時は `flutter gen-l10n` 済みで、`app/lib/src/generated/l10n/` は生成差分のみである
- [ ] icon-only controlのtooltip/semantics、48px級タップ領域、色だけに依存しない情報伝達が維持されている（UI変更時）
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない
- [ ] `todori-private/` と `.github/` が変更されていない（指示書に明記がある場合を除く）
- [ ] public repoにprivate詳細（課金、収益、法務、監査、公開前ロードマップ）が転記されていない
- [ ] 新規依存（pub / crate）が指示書の明記なしに追加されていない
- [ ] 指示書末尾に `## 9. 完了報告` が追記されている

追加ルール: **タスク固有の受け入れ基準には、観測可能な証拠を要求する項目を1つ以上含める**（UI変更ならスクショ、性能なら数値、挙動ならテスト/ログ。文章による自己申告だけで完結する基準にしない）。

## 完了報告の規約

- 完了時は当該指示書ファイルの冒頭（タイトル直下）に `> ステータス: 完了（...）` と `> 作業日: YYYY-MM-DD` を追記し、このタスク一覧のステータス列も更新する。
- 各タスクの実行者は、完了時に当該指示書ファイルの末尾へ「## 9. 完了報告」を追記する（体裁はtask-01〜10の実例に倣う）。
- 必ず含める: 作業日、実装結果、8章（完了報告に含めるべき内容）で要求された項目、検証結果（品質ゲートの実行結果）、未解決事項。
- 未解決事項は次タスクの入力になるため、無い場合も「なし」と明記する。
- 完了報告は**事実のみ**を記録する: 変更ファイル、実行コマンドと結果、スクショ/数値等の証拠のパス、未解決事項。「プロダクト品質になった」「十分改善された」等の品質評価語は書かない。品質達成の判定は検証セッション・親・人間だけが記録する。
