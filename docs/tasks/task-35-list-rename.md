# task-35: リスト名称変更 ── M3-01完了条件の残り(1/2)

## 1. 背景とコンテキスト

2026-07-06のPhase1計画とのギャップ棚卸し（`docs/tasks/BACKLOG.md` 優先度付きバックログ #1）で、M3-01完了条件（リスト作成/名称変更/削除）のうち**作成のみ**実装済みであることが判明した。出典: `docs/tasks/BACKLOG.md` 「現在地」節、および優先度付きバックログ表の #1（「リスト名称変更UI」「出典: M3-01完了条件（作成/名称変更/削除のうち作成のみ実装済み。2026-07-06親棚卸しで確認）」）。

本タスクはM3-01残り2条件のうち**名称変更のみ**を実装する。リスト削除は2026-07-07人間裁定（`docs/design/ui-spec.md` 裁定済み事項「データ保持原則」）によりセマンティクスが変更され、スキーマ変更（`lists.deleted_at` 新設）とマイグレーション機構を前提とするため task-37 へ分離した（task-36=DBスキーママイグレーション機構の整備が先行する）。

現状の実装範囲（本タスク前提の事実確認）:

- bridge層（`app/rust/src/api.rs`）には `create_list` / `get_lists` のみが存在し、リスト名称変更のbridge APIが存在しない。
- `core/domain/src/usecases.rs` には既に **`rename_list` ユースケースと単体テストが実装済み**である（`rename_list_changes_name_and_updated_at` / `rename_list_rejects_empty_name`）。
- Dart側 `BridgeService`（`app/lib/src/core/bridge_service.dart`）・`FakeBridgeService`（`app/test/support/fake_bridge_service.dart`）・`listsProvider`（`app/lib/src/core/providers.dart`）にもリスト名称変更の導線がない。
- Lists画面（`app/lib/src/screens/lists_screen.dart`）の各行はタップで遷移するのみで、改名の操作導線がない。

このタスクは domain（実装済み確認）→ storage（rename反映確認）→ FRB bridge → Dart provider → UI の縦貫通実装により、M3-01の残り条件のうち名称変更を実装する。

### 既定インボックス保護について（F-09を根拠にした暫定解）

`docs/02_機能仕様書.md` F-09は次のように定める:「ユーザーは複数のリストを作成できる。リストは名前・色・アイコンを設定可能とする。初期状態では『インボックス』リストがデフォルトとして用意され、リスト未指定のタスクの受け皿となる。」

これを実装済みコードと突き合わせると、以下の**ギャップと暫定解**がある。実装者は以下の解釈で進めること（仕様の厳密な確定は完了報告の未解決事項に記録する）。

1. **F-09が想定する「インボックスの自動プロビジョニング」は現状未実装である**（既知のギャップ、本タスクのスコープ外）。`HomeScreen` / `ListsScreen` は現状、ユーザーが初回に手動でリストを作成するまで空状態を表示する（`app/lib/src/screens/home_screen.dart` の `_HomeEmptyScreen`）。本タスクはこの自動プロビジョニングを新規実装**しない**（スコープ外。以下「4. スコープ」参照）。
2. `List` エンティティ（`core/domain/src/entities.rs`）・`lists` テーブル（`core/storage/src/schema.sql`）には「これが既定インボックスである」ことを示すフラグ列が存在しない。バックログのDBスキーママイグレーション機構整備（task-36）が未着手のため、本タスクで新規スキーマ列を追加すること（マイグレーション機構なしでのスキーマ変更）は避ける。
3. **本タスクの暫定解**: 「既定インボックス」を、`list_all()`（`ORDER BY sort_order ASC`）で得られる**先頭のリスト（`sort_order` が最小のリスト）**と定義する。これは既存UIが既に暗黙に採用している扱いと一致する（`lists_screen.dart` の `index == 0` に太陽アイコンを割り当てる分岐、`home_screen.dart` の `lists.first` をホーム表示対象にする分岐）。リストの並び替えAPIは現状存在しないため、この定義は「最初に作成されたリスト」と実質的に同値であり、当面安定する。
4. 既定インボックスの**名称変更**は許可する（F-09は名称変更を禁止していない）。既定インボックスの**削除**保護・削除セマンティクスは task-37 のスコープであり、本タスクでは扱わない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`（優先度付きバックログ #1、現在地セクション）
- `docs/02_機能仕様書.md` F-09（リスト）
- `docs/design/ui-spec.md`（セクション1〜4のDialog規範、裁定済み事項）
- `core/domain/src/usecases.rs`（既存の `rename_list`、`DomainError`）
- `core/storage/src/lib.rs`（`ListRepository` trait、`SqliteListRepository::update` 実装）
- `app/rust/src/api.rs`（現状の `create_list` / `get_lists` と、他APIの `with_list_repository` パターン）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`（`ListsNotifier` の invalidate 方針）
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/dialogs.dart`（`showAppTextInputDialog`）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`（既存のLists画面関連テスト）
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（`lists` スクリーンショット）と `app/tool/visual_qa.sh`

## 3. ゴール

- Lists画面の各リスト行から名称変更が実行でき、Rust/SQLCipher DBへ反映される。
- 既定インボックス（先頭のリスト）を含め、すべてのリストで名称変更が可能である。
- FRBブリッジ・Dart provider・UIが一気通貫で動作し、既存のFlutterテストを壊さない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/rust/src/api.rs`（`rename_list` 追加）
- `flutter_rust_bridge.yaml` 経由で再生成される `app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下（手編集禁止、生成のみ）
- `app/lib/src/core/bridge_service.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/dialogs.dart`（`showAppTextInputDialog` にプリフィル値対応を追加する場合）
- `app/lib/l10n/app_en.arb` / `app/lib/l10n/app_ja.arb`（`flutter gen-l10n` 後、`app/lib/src/generated/l10n/` は生成差分のみ）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（既存 `lists` スクリーンショットの見直しが必要な場合のみ）
- `docs/tasks/task-35-list-rename.md`（完了報告の追記のみ）

### やること

1. **`core/domain`**:
   - `rename_list` は実装済みのため追加実装は不要（読んで単体テストの内容を確認するのみ）。
2. **`core/storage`**:
   - `ListRepository::update` が名称変更（`name` + `updated_at`）を正しく永続化することを確認する。追加実装が必要な場合のみ行う（既存実装で足りる場合は変更不要）。
3. **`app/rust/src/api.rs`**:
   - `rename_list(list_id: String, name: String) -> Result<ListDto, String>` を追加する。既存の `domain_delete_task` 等のエイリアスパターンに倣い、`todori_domain::rename_list` を `use ... as domain_rename_list;` でインポートして名前衝突を避ける。
   - 変更後、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行して生成物を更新する（FRB `2.12.0` 固定、手編集禁止）。
4. **Dart（bridge / provider）**:
   - `BridgeService`（`app/lib/src/core/bridge_service.dart`）に `renameList` を追加し、`FrbBridgeService` 実装と `FakeBridgeService`（`app/test/support/fake_bridge_service.dart`）の両方に実装する。
   - `ListsNotifier`（`app/lib/src/core/providers.dart`）に `renameList` メソッドを追加し、成功後は `listsProvider` を invalidate する。
5. **UI（Lists画面）**:
   - `docs/design/ui-spec.md` セクション4の判断規則・セクション1「Dialog」規範（文章主体、装飾なし）に従い、各リスト行に控えめな改名導線を追加する（例: 行の trailing に `PopupMenuButton` または長押しメニューで「名称変更」を提示する。既存の chevron 遷移との衝突を避けること）。
   - 現在のリスト名をプリフィルした入力ダイアログを表示する。`showAppTextInputDialog` に `initialValue` 相当のオプション引数を追加するか、同等の新規ダイアログ関数を追加する。
   - 既定インボックス行（`lists.first`）でも名称変更メニューは表示・有効のままにする。
6. **l10n / test**:
   - 名称変更に関するUI文字列をen/ja両方のARBへ追加し `flutter gen-l10n` を実行する（`app/lib/src/generated/l10n/` は生成差分のみ）。
   - widget testを追加する: (a) 名称変更がLists画面・FakeBridgeServiceへ反映される、(b) 既定インボックスでも改名メニューが選択でき反映される、(c) 長いリスト名でも改名ダイアログが破綻しない。
7. **visual QA**:
   - 作業開始前に既存の `app/build/visual_qa/` があれば `app/build/visual_qa_before/` へ退避する。
   - `sh app/tool/visual_qa.sh` を実行し、`lists.png` を含む全スクリーンショットを生成する。
   - `lists.png` を目視確認し、追加した操作導線（メニュー等）がui-spec.mdの色数・装飾規則を逸脱していないかを確認し、結果を完了報告に記録する。

### やらないこと

- リストの削除（論理削除・完了済みタスク保全・未完了タスクのゴミ箱送り・復元時の既定インボックスremap）。これらは2026-07-07人間裁定によりスキーマ変更（`lists.deleted_at`）を前提とするため task-37 のスコープとする。
- リストの並び替え（ドラッグ&ドロップ等）UI・API。
- リストのアーカイブ機能。
- タスク側UI（wont_do/再オープン等、バックログ相当の別タスク）の変更。
- 既定インボックスの自動プロビジョニング機構の新規実装（上記「既定インボックス保護について」1節参照。既存のバックログ・別タスクの対象）。
- `lists` テーブルへの新規スキーマ列（`is_default` / `deleted_at` 等）の追加（task-36 のマイグレーション機構整備が前提）。
- 新規pub/crate依存の追加。
- `docs/01〜03`、`todori-private/`、`.github/` の変更。
- Lists画面・Home画面以外のスコープ外画面（Tasks/Detail/Trash等）の見た目変更。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認する。
2. `docs/02_機能仕様書.md` F-09、`core/domain/src/usecases.rs` の `rename_list` を読み、既存実装の形を確認する。
3. `core/storage/src/lib.rs` の `ListRepository::update` が名称変更に対応済みであることを確認する。
4. `app/rust/src/api.rs` に `rename_list` を追加する。
5. リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成差分のみであることを `git diff` で確認する。
6. `app/lib/src/core/bridge_service.dart` / `app/test/support/fake_bridge_service.dart` / `app/lib/src/core/providers.dart` を更新する。
7. `app/lib/src/screens/lists_screen.dart` に改名導線・ダイアログ呼び出しを追加し、必要なら `app/lib/src/ui/dialogs.dart` を拡張する。
8. en/ja ARBへ文字列を追加し `flutter gen-l10n` を実行する。
9. `app/test/widget_test.dart` にテストを追加する。
10. `app/build/visual_qa/` を退避 → `sh app/tool/visual_qa.sh` 実行 → `lists.png` を含む出力を目視確認する。
11. 品質ゲート（後述「共通受け入れ基準」参照）を実行する。
12. 指示書末尾に完了報告を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] UI（Lists画面）からリスト名を変更すると、DB（SQLCipher）への永続化と `lists.png` 再生成後の表示に反映されている。
- [ ] 既定インボックス（`sort_order` 最小のリスト）でも名称変更が可能であることがwidget testで確認できる。
- [ ] `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 実行後の生成物差分が `frb_generated.*` / `app/lib/src/rust/` 配下のみであり、手編集がない。
- [ ] `FakeBridgeService` と実体 `FrbBridgeService` の両方が `renameList` を実装し、対応するテストが通過する。
- [ ] before/after の `lists.png`（`app/build/visual_qa_before/` / `app/build/visual_qa/`）を目視確認した結果が完了報告に記録されている。
- [ ] 既存のFlutterテスト・既存Rustテストが引き続き成功する（テスト総数の増減を完了報告に記録する）。

## 7. 制約・注意事項

- FRBは `2.12.0` 固定である。Rust側crate（`flutter_rust_bridge`）・Dart側pub（`flutter_rust_bridge`）のバージョンを変更しない。
- 生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）は手編集しない。差分は再生成コマンドのみで作る。
- 既定インボックスの識別は「`sort_order` が最小のリスト」という構造的な暫定解であり、`name` による判定（例: `"Inbox"` / `"インボックス"` 文字列一致）は行わない（ローカライズ・改名により崩れるため）。
- リスト削除には一切着手しない。削除ボタン・削除確認ダイアログ・削除API・`ListRepository::delete` 等の実装は本タスクのスコープ外であり、task-37で扱う。
- 秘密情報、Device Key、SQLCipher鍵をログ・Debug出力に含めない。
- `docs/01〜03` は変更禁止。実装中に仕様との矛盾を発見した場合は書き換えず完了報告の未解決事項に記録する。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親が行う。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する（「プロダクト品質になった」等の品質評価語は書かない）。以下を含めること。

- 作業日、読んだファイル
- F-09から読み取った名称変更セマンティクス・既定インボックス保護の判断根拠（本指示書「既定インボックス保護について」1〜4節参照。逸脱した場合はその内容）
- `core/domain` の `rename_list` 実装・単体テストの確認結果
- `core/storage` の `ListRepository::update` が名称変更に対応していることの確認結果
- `app/rust/src/api.rs` に追加した `rename_list` のシグネチャ
- FRB再生成コマンドの実行結果と生成差分の概要（`git diff --stat` 相当）
- Dart側の変更内容（`BridgeService` / `FakeBridgeService` / `ListsNotifier` / UI）
- 追加/更新したl10nキーとwidget testの対象・結果
- before/afterの `lists.png` 保存パスと目視確認結果
- 品質ゲートの実行結果一覧
- 未解決事項（既定インボックス自動プロビジョニングの要否等を含む）
