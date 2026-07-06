# task-35: リスト名称変更・削除 ── M3-01完了条件の残り

## 1. 背景とコンテキスト

2026-07-06のPhase1計画とのギャップ棚卸し（`docs/tasks/BACKLOG.md` 優先度付きバックログ #1）で、M3-01完了条件（リスト作成/名称変更/削除）のうち**作成のみ**実装済みであることが判明した。出典: `docs/tasks/BACKLOG.md` 「現在地」節、および優先度付きバックログ表の #1（「リスト名称変更・削除UI」「出典: M3-01完了条件（作成/名称変更/削除のうち作成のみ実装済み。2026-07-06親棚卸しで確認）」）。

現状の実装範囲（本タスク前提の事実確認）:

- bridge層（`app/rust/src/api.rs`）には `create_list` / `get_lists` のみが存在し、リスト名称変更・削除のbridge APIが存在しない。
- `core/domain/src/usecases.rs` には既に **`rename_list` ユースケースと単体テストが実装済み**である（`rename_list_changes_name_and_updated_at` / `rename_list_rejects_empty_name`）。リスト削除のユースケースは存在しない。
- `core/storage` の `ListRepository` trait（`core/storage/src/lib.rs`）は `get` / `insert` / `update` / `list_all` のみで、削除メソッドが存在しない。
- Dart側 `BridgeService`（`app/lib/src/core/bridge_service.dart`）・`FakeBridgeService`（`app/test/support/fake_bridge_service.dart`）・`listsProvider`（`app/lib/src/core/providers.dart`）にもリスト名称変更・削除の導線がない。
- Lists画面（`app/lib/src/screens/lists_screen.dart`）の各行はタップで遷移するのみで、改名・削除の操作導線がない。

このタスクは domain → storage → FRB bridge → Dart provider → UI の縦貫通実装により、M3-01の残り2条件（名称変更・削除）を実装する。

### 既定インボックス保護について（F-09を根拠にした暫定解）

`docs/02_機能仕様書.md` F-09は次のように定める:「ユーザーは複数のリストを作成できる。リストは名前・色・アイコンを設定可能とする。初期状態では『インボックス』リストがデフォルトとして用意され、リスト未指定のタスクの受け皿となる。」

これを実装済みコードと突き合わせると、以下の**ギャップと暫定解**がある。実装者は以下の解釈で進めること（仕様の厳密な確定は完了報告の未解決事項に記録する）。

1. **F-09が想定する「インボックスの自動プロビジョニング」は現状未実装である**（既知のギャップ、本タスックのスコープ外）。`HomeScreen` / `ListsScreen` は現状、ユーザーが初回に手動でリストを作成するまで空状態を表示する（`app/lib/src/screens/home_screen.dart` の `_HomeEmptyScreen`）。本タスクはこの自動プロビジョニングを新規実装**しない**（スコープ外。以下「4. スコープ」参照）。
2. `List` エンティティ（`core/domain/src/entities.rs`）・`lists` テーブル（`core/storage/src/schema.sql`）には「これが既定インボックスである」ことを示すフラグ列が存在しない。バックログ #5（DBスキーママイグレーション機構の整備）が未着手のため、本タスクで新規スキーマ列を追加すること（マイグレーション機構なしでのスキーマ変更）は避ける。
3. **本タスクの暫定解**: 「既定インボックス」を、`list_all()`（`ORDER BY sort_order ASC`）で得られる**先頭のリスト（`sort_order` が最小のリスト）**と定義する。これは既存UIが既に暗黙に採用している扱いと一致する（`lists_screen.dart` の `index == 0` に太陽アイコンを割り当てる分岐、`home_screen.dart` の `lists.first` をホーム表示対象にする分岐）。リストの並び替えAPIは現状存在しないため、この定義は「最初に作成されたリスト」と実質的に同値であり、当面安定する。
4. 削除保護の対象は「既定インボックスの**削除**」のみとする。既定インボックスの**名称変更**は許可する（F-09は名称変更を禁止していない）。この非対称（削除は不可・改名は可）は仕様上明記されていないため完了報告の未解決事項に記録すること。
5. リスト削除時の配下タスクの扱い: F-09の「リスト未指定のタスクの受け皿となる」という文言を、リスト削除により行き場を失うタスクの扱いへ拡張解釈し、**削除対象リストに属する全タスク（アクティブ・ゴミ箱内の両方）を既定インボックスへ `list_id` 付け替えする**（タスク自体は削除しない）。F-07（ゴミ箱・Undo）が定めるタスクの論理削除とは別の話であり、リスト削除によってタスクを巻き添えでゴミ箱送りにする実装は行わない（暫定解。カスケード論理削除案も検討したが、ユーザーデータを保全する方を優先した。完了報告の未解決事項に記録すること）。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`（優先度付きバックログ #1、現在地セクション）
- `docs/02_機能仕様書.md` F-09（リスト）、F-06（サブタスク）、F-07（ゴミ箱・Undo）
- `docs/design/ui-spec.md`（セクション1〜4のDialog規範・destructive coral規則、裁定済み事項）
- `core/domain/src/entities.rs`（`List` / `Task` エンティティ）
- `core/domain/src/usecases.rs`（既存の `rename_list`、`DomainError`）
- `core/storage/src/lib.rs`（`ListRepository` trait、`SqliteListRepository` 実装、`TaskRepository` の `list_active_by_list` / `list_trashed`）
- `core/storage/src/schema.sql`
- `app/rust/src/api.rs`（現状の `create_list` / `get_lists` と、他APIの `with_list_repository` / `with_task_repository` パターン）
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`（`ListsNotifier` / `TasksNotifier` の invalidate 方針）
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/home_screen.dart`（`lists.first` の扱い）
- `app/lib/src/ui/dialogs.dart`（`showAppTextInputDialog` / `showAppConfirmDialog`）
- `app/test/support/fake_bridge_service.dart`
- `app/test/widget_test.dart`（既存のLists画面・確認ダイアログ関連テスト）
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（`lists` スクリーンショット）と `app/tool/visual_qa.sh`

## 3. ゴール

- Lists画面の各リスト行から名称変更・削除が実行でき、Rust/SQLCipher DBへ反映される。
- 削除時、配下タスク（アクティブ・ゴミ箱内問わず）は既定インボックスへ再割り当てされ、消失しない。
- 既定インボックス（先頭のリスト）はUI・API双方で削除できない。
- FRBブリッジ・Dart provider・UIが一気通貫で動作し、既存の37件超のテストを壊さない。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `core/domain/src/usecases.rs`（削除ガード関数・`DomainError`追加、単体テスト）
- `core/storage/src/lib.rs`（`ListRepository::delete`、統合テスト）
- `app/rust/src/api.rs`（`rename_list` / `delete_list` 追加）
- `flutter_rust_bridge.yaml` 経由で再生成される `app/rust/src/frb_generated.rs`、`app/lib/src/rust/` 配下（手編集禁止、生成のみ）
- `app/lib/src/core/bridge_service.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/ui/dialogs.dart`（`showAppTextInputDialog` にプリフィル値対応を追加する場合）
- `app/lib/l10n/app_en.arb` / `app/lib/l10n/app_ja.arb`（`flutter gen-l10n` 後、`app/lib/src/generated/l10n/` は生成差分のみ）
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`（既存 `lists` スクリーンショットの見直しが必要な場合のみ）
- `docs/tasks/task-35-list-rename-delete.md`（完了報告の追記のみ）

### やること

1. **`core/domain`**:
   - `rename_list` は実装済みのため追加実装は不要（読んで確認するのみ）。
   - リスト削除の**ガード関数**を追加する。例: `ensure_list_deletable(list_id: Uuid, default_list_id: Uuid) -> Result<(), DomainError>`。`list_id == default_list_id` の場合は新しい `DomainError`（例: `CannotDeleteDefaultList`）を返す。純粋関数として単体テストを2ケース以上追加する（削除可能なケース・既定インボックスで拒否されるケース）。
   - 上記「既定インボックス保護について」1〜5節の解釈をこの実装の根拠として踏襲すること。
2. **`core/storage`**:
   - `ListRepository` trait に `delete` を追加する（シグネチャ例: `fn delete(&mut self, list_id: Uuid, fallback_list_id: Uuid, now_ms: i64) -> Result<(), StorageError>`。実装は同一SQLite接続内のトランザクションで (a) `list_id` に属する全タスク（アクティブ・ゴミ箱内問わず、`deleted_at` を問わない）の `list_id` を `fallback_list_id` へ付け替え `updated_at` を更新し、(b) `lists` テーブルから対象行を削除する。対象リストが存在しない場合は `StorageError::NotFound` を返す。
   - 統合テストを追加する: 削除対象リストのアクティブタスク・ゴミ箱内タスク双方が既定リストへ再割り当てされること、削除後に対象リストが `list_all()` に現れないこと、存在しないリストIDの削除が `NotFound` を返すこと。
3. **`app/rust/src/api.rs`**:
   - `rename_list(list_id: String, name: String) -> Result<ListDto, String>` を追加する。既存の `domain_delete_task` 等のエイリアスパターンに倣い、`todori_domain::rename_list` を `use ... as domain_rename_list;` でインポートして名前衝突を避ける。
   - `delete_list(list_id: String) -> Result<(), String>` を追加する。実装は (a) `list_all()` で全リストを取得し先頭（`sort_order` 最小）を既定インボックスとする、(b) `ensure_list_deletable` で対象が既定インボックスでないか検証する、(c) `ListRepository::delete` を呼ぶ。
   - 変更後、リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行して生成物を更新する（FRB `2.12.0` 固定、手編集禁止）。
4. **Dart（bridge / provider）**:
   - `BridgeService`（`app/lib/src/core/bridge_service.dart`）に `renameList` / `deleteList` を追加し、`FrbBridgeService` 実装と `FakeBridgeService`（`app/test/support/fake_bridge_service.dart`）の両方に実装する。`FakeBridgeService` の削除実装も、既定インボックス保護・タスク再割り当てのロジックを模倣すること（本番ロジックと矛盾するテストにしない）。
   - `ListsNotifier`（`app/lib/src/core/providers.dart`）に `renameList` / `deleteList` メソッドを追加する。削除後は `listsProvider` の invalidate に加え、削除対象リストの `tasksProvider`、既定インボックスの `tasksProvider`、`trashedTasksProvider` も invalidate する（再割り当てされたタスクを画面へ反映するため）。
5. **UI（Lists画面）**:
   - `docs/design/ui-spec.md` セクション4の判断規則・セクション1「Dialog」規範（文章主体、装飾なし、destructiveのみcoral）に従い、各リスト行に控えめな操作導線を追加する（例: 行の trailing に `PopupMenuButton` または長押しメニューで「名称変更」「削除」を提示する。既存の chevron 遷移との衝突を避けること）。
   - 名称変更: 現在のリスト名をプリフィルした入力ダイアログを表示する。`showAppTextInputDialog` に `initialValue` 相当のオプション引数を追加するか、同等の新規ダイアログ関数を追加する。
   - 削除: `showAppConfirmDialog` を用いた確認ダイアログを表示する。確認ボタンの配色は `docs/design/ui-spec.md` の destructive coral (`#E8755A`) 規則に従う。
   - 既定インボックス行（`lists.first`）には削除メニュー項目を表示しない、または無効化する。名称変更は既定インボックスでも可能なままにする。
6. **l10n / test**:
   - 名称変更・削除に関するUI文字列をen/ja両方のARBへ追加し `flutter gen-l10n` を実行する（`app/lib/src/generated/l10n/` は生成差分のみ）。
   - widget testを追加する: (a) 名称変更がLists画面・FakeBridgeServiceへ反映される、(b) 削除確認後にリストが消え配下タスクが既定インボックス側へ現れる、(c) 既定インボックスに削除導線が出ない/選べない、(d) 長いリスト名でも改名ダイアログ・確認ダイアログが破綻しない。
7. **visual QA**:
   - 作業開始前に既存の `app/build/visual_qa/` があれば `app/build/visual_qa_before/` へ退避する。
   - `sh app/tool/visual_qa.sh` を実行し、`lists.png` を含む全スクリーンショットを生成する。
   - `lists.png` を目視確認し、追加した操作導線（メニュー等）がui-spec.mdの色数・装飾規則を逸脱していないかを確認し、結果を完了報告に記録する。

### やらないこと

- リストの並び替え（ドラッグ&ドロップ等）UI・API。
- リストのアーカイブ機能。
- タスク側UI（wont_do/再オープン等、バックログ #2 = task-36相当）の変更。
- 既定インボックスの自動プロビジョニング機構の新規実装（上記「既定インボックス保護について」1節参照。既存のバックログ・別タスクの対象）。
- `lists` テーブルへの新規スキーマ列（`is_default` 等）の追加（バックログ #5 のマイグレーション機構整備が前提）。
- 新規pub/crate依存の追加。
- `docs/01〜03`、`todori-private/`、`.github/` の変更。
- Lists画面・Home画面以外のスコープ外画面（Tasks/Detail/Trash等）の見た目変更。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認する。
2. `docs/02_機能仕様書.md` F-09、`core/domain/src/usecases.rs`、`core/storage/src/lib.rs` を読み、既存の `rename_list` と `ListRepository` の形を確認する。
3. `core/domain/src/usecases.rs` に削除ガード関数と `DomainError` variant、単体テストを追加する。`cargo test -p todori-domain` で確認する。
4. `core/storage/src/lib.rs` の `ListRepository` trait に `delete` を追加し、`SqliteListRepository` へトランザクション実装、統合テストを追加する。`cargo test -p todori-storage` で確認する。
5. `app/rust/src/api.rs` に `rename_list` / `delete_list` を追加する。
6. リポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成差分のみであることを `git diff` で確認する。
7. `app/lib/src/core/bridge_service.dart` / `app/test/support/fake_bridge_service.dart` / `app/lib/src/core/providers.dart` を更新する。
8. `app/lib/src/screens/lists_screen.dart` に操作導線・ダイアログ呼び出しを追加し、必要なら `app/lib/src/ui/dialogs.dart` を拡張する。
9. en/ja ARBへ文字列を追加し `flutter gen-l10n` を実行する。
10. `app/test/widget_test.dart` にテストを追加する。
11. `app/build/visual_qa/` を退避 → `sh app/tool/visual_qa.sh` 実行 → `lists.png` を含む出力を目視確認する。
12. 品質ゲート（後述「共通受け入れ基準」参照）を実行する。
13. 指示書末尾に完了報告を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] UI（Lists画面）からリスト名を変更すると、DB（SQLCipher）への永続化と `lists.png` 再生成後の表示に反映されている。
- [ ] UI（Lists画面）からリストを削除すると、当該リストがDBから消え、配下タスク（アクティブ・ゴミ箱内双方）が既定インボックスの `list_id` へ再割り当てされていることがstorage統合テストで確認できる。
- [ ] 既定インボックス（`sort_order` 最小のリスト）はUI上で削除メニューが提示されない、または選択できない。
- [ ] `delete_list` API を既定インボックスのIDで直接呼んでもエラーで拒否される（UI経由を回避してもAPI側で保護される）widget/domainテストがある。
- [ ] `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 実行後の生成物差分が `frb_generated.*` / `app/lib/src/rust/` 配下のみであり、手編集がない。
- [ ] `FakeBridgeService` と実体 `FrbBridgeService` の両方が `renameList` / `deleteList` を実装し、対応するテストが通過する。
- [ ] before/after の `lists.png`（`app/build/visual_qa_before/` / `app/build/visual_qa/`）を目視確認した結果が完了報告に記録されている。
- [ ] 既存の37件超のFlutterテスト・既存Rustテストが引き続き成功する（テスト総数の増減を完了報告に記録する）。

## 7. 制約・注意事項

- FRBは `2.12.0` 固定である。Rust側crate（`flutter_rust_bridge`）・Dart側pub（`flutter_rust_bridge`）のバージョンを変更しない。
- 生成物（`frb_generated.*`、`app/lib/src/rust/` 配下）は手編集しない。差分は再生成コマンドのみで作る。
- リスト削除はタスクのデータ消失を伴ってはならない（本タスクの暫定解: 既定インボックスへの再割り当て）。カスケード論理削除など別の解釈を採る場合は、その判断根拠と代替案を完了報告に明記すること。
- 既定インボックスの識別は「`sort_order` が最小のリスト」という構造的な暫定解であり、`name` による判定（例: `"Inbox"` / `"インボックス"` 文字列一致）は行わない（ローカライズ・改名により崩れるため）。
- 秘密情報、Device Key、SQLCipher鍵をログ・Debug出力に含めない。
- `docs/01〜03` は変更禁止。実装中に仕様との矛盾を発見した場合は書き換えず完了報告の未解決事項に記録する。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親が行う。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する（「プロダクト品質になった」等の品質評価語は書かない）。以下を含めること。

- 作業日、読んだファイル
- F-09から読み取った削除セマンティクス・既定インボックス保護の判断根拠（本指示書「既定インボックス保護について」1〜5節と実装が一致しているか、逸脱した場合はその内容）
- `core/domain` に追加した関数・`DomainError` variant・単体テスト結果
- `core/storage` の `ListRepository::delete` 実装内容（トランザクション境界、再割り当て対象の範囲）と統合テスト結果
- `app/rust/src/api.rs` に追加した `rename_list` / `delete_list` のシグネチャ
- FRB再生成コマンドの実行結果と生成差分の概要（`git diff --stat` 相当）
- Dart側の変更内容（`BridgeService` / `FakeBridgeService` / `ListsNotifier` / UI）
- 追加/更新したl10nキーとwidget testの対象・結果
- before/afterの `lists.png` 保存パスと目視確認結果
- 品質ゲートの実行結果一覧
- 未解決事項（既定インボックス改名可否、カスケード削除案との比較、既定インボックス自動プロビジョニングの要否等を含む）
