# task-09: Flutter画面骨格と状態管理（Riverpod）の確立（M2-03）

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM2「ブリッジとUI骨格」は、M2-03「Flutterの画面遷移骨格と状態管理方針を実装する」を定義している（完了条件: リスト一覧、タスク一覧、タスク詳細へ遷移できるwidget testが通ること）。このタスクは同項目に対応する。

task-08で `taskveil-app-bridge` にリスト/タスク操作のユースケース単位API（`initCore` / `createList` / `getLists` / `createTask` / `getTasks` / `setTaskStatus` / `trashTask` / `restoreTask` / `getTrashedTasks`）がDart側へ公開済みである。本タスクはこのブリッジAPIの上に、Flutterアプリの画面遷移骨格（リスト一覧→タスク一覧→タスク詳細）と状態管理方針を確立する。状態管理はRiverpodの採用が決定済みであり、`riverpod_generator` は使わず素の記法（`AsyncNotifier` / `AsyncNotifierProvider` / `Provider`）を用いる（コード生成をビルドパイプラインに増やさないため）。ルーティングは `go_router` を用いる。依存パッケージ（`flutter_riverpod ^3.3.2` / `go_router ^17.3.0` / `path_provider ^2.1.6`）は既に `app/pubspec.yaml` に追加済みであり、本タスクの実行環境はネットワークアクセス不可であるためこれ以上の新規パッケージ追加は行わない。

本タスクはUIの「骨格」を確立するものであり、デザインの磨き込みや全機能CRUD UIは `docs/07_Phase1計画書.md` M3の範囲である。

## 2. 事前に読むべきファイル

- `docs/tasks/task-08-bridge-usecases.md`（本タスクの前提となるブリッジAPI公開の指示書と完了報告）
- `app/lib/main.dart`（既存のFRB初期化・カウンターアプリの雛形）
- `app/lib/src/rust/api.dart`（FRB生成API: `initCore` / `createList` / `getLists` / `createTask` / `getTasks` / `setTaskStatus` / `trashTask` / `restoreTask` / `getTrashedTasks` / `greet`、および `ListDto` / `TaskDto` の型定義）
- `app/test/rust_bridge_test.dart` / `app/test/core_usecases_test.dart`（既存Dartテストの流儀。`RustLib.init()` の呼び出し方、`initCore` の使い方）
- `app/pubspec.yaml`（`flutter_riverpod ^3.3.2` / `go_router ^17.3.0` / `path_provider ^2.1.6` が追加済みであることの確認）
- `docs/07_Phase1計画書.md` M2セクション（M2-01〜M2-04の完了条件）、および§5「UIモード切替の設計負債化」（Phase 1では状態管理とルーティングにモード拡張点だけ用意し、高機能画面は実装しない方針）
- `docs/02_機能仕様書.md` F-02「シンプルUI」（リスト・タスク・完了チェックのみで構成する最小構成のUIとする方針）

## 3. ゴール

`app/lib/` にRiverpodベースの状態管理層とgo_routerベースの画面遷移骨格を実装し、リスト一覧→タスク一覧→タスク詳細の3画面へ遷移できることをwidget testで実証する。widget testはネイティブライブラリ・`initCore` に依存せず、フェイクの `BridgeService` をProviderScopeでoverrideして実行できること。`cd app && flutter analyze` と `cd app && flutter test` の双方が緑になること。

## 4. スコープ

### やること

1. **ブリッジ抽象層**: `app/lib/src/core/bridge_service.dart`（新規）に抽象クラス `BridgeService` を定義し、FRB生成関数（`createList` / `getLists` / `createTask` / `getTasks` / `setTaskStatus` / `trashTask` / `restoreTask` / `getTrashedTasks`）をラップする実装 `FrbBridgeService` を作る。目的はwidget testがネイティブライブラリ無しでフェイク実装に差し替えられるようにすること（ProviderScopeのoverride）。DTO型は `app/lib/src/rust/api.dart` のFRB生成 `ListDto` / `TaskDto` をそのまま使う。
2. **Riverpod providers**: `app/lib/src/core/providers.dart`（新規）に以下を実装する。
   - `bridgeServiceProvider = Provider<BridgeService>`（既定は `FrbBridgeService`）
   - `listsProvider = AsyncNotifierProvider<ListsNotifier, List<ListDto>>`（リスト一覧の取得。`createList` 呼び出し成功後は `ref.invalidateSelf()` で自身を再取得する）
   - `tasksProvider = AsyncNotifierProvider.family<TasksNotifier, List<TaskDto>, String>`（`listId` 別のactiveタスク一覧。`createTask` / `setStatus` / `trashTask` 呼び出し成功後は `ref.invalidateSelf()` で自身を再取得する）
   - `taskDetailProvider = Provider.family<AsyncValue<TaskDto?>, TaskDetailArgs>`（タスク詳細用。`tasksProvider` の結果を `ref.watch` して該当タスクをクライアント側で検索する方針とする。専用のget-by-idブリッジAPIが存在しないため、単一のキャッシュ/正とする発想で `tasksProvider` から導出する旨をコメントに明記する）
   - 変更系操作（`createList` / `createTask` / `setTaskStatus` / `trashTask`）はNotifierのメソッドとして実装し、ブリッジ呼び出し成功後に `ref.invalidateSelf()` で関連providerを再取得する方針を各クラスのdocコメントに明記する
3. **アプリ初期化**: `app/lib/main.dart` を書き換える。`main()` で `RustLib.init()` → `path_provider` の `getApplicationSupportDirectory()` 配下のディレクトリで `initCore` → `ProviderScope` + `MaterialApp.router` を起動する。初期化失敗時は素朴なエラー画面を表示する。既存のカウンター/greeting表示は削除する。ルーター/ProviderScopeを注入可能なトップレベルwidget `TaskveilApp` に分離し、widget testからは初期化なし・フェイク `BridgeService` のoverrideのみで組み立てられる構造にする。
4. **go_routerルーティング**: `app/lib/src/router.dart`（新規）を作成する。ルートは `/lists`（初期）→ `/lists/:listId/tasks` → `/lists/:listId/tasks/:taskId`（詳細）とする。UIモード拡張点（Phase 3、`docs/07_Phase1計画書.md` §5参照）としてルート定義を一箇所に集約する旨をコメントに明記する。
5. **画面3枚**（`app/lib/src/screens/` 配下、シンプルUI・Material 3の素朴なwidgetでよい）を実装する。
   - `lists_screen.dart`: リスト一覧（`AsyncValue` のloading/error/data三態を素直に描画する）。FAB→ダイアログでリスト名入力→作成する。`sort_order` は暫定で `'a0'`, `'a1'`... のような単純連番文字列を生成するヘルパーでよい（fractional index本実装はM3である旨コメントに明記する）。タップでタスク一覧へ遷移する。
   - `tasks_screen.dart`: 指定リストのactiveタスク一覧。FAB→ダイアログでタスク作成する。チェックボックスでdone遷移させ、doneにしたら一覧をinvalidateする。タップで詳細へ遷移する。
   - `task_detail_screen.dart`: タスクの主要フィールド（title/note/status/priority/created_at等）を表示する。「ゴミ箱へ」ボタンで `trashTask` を呼び、タスク一覧へ戻る。
6. **widget test**: `app/test/widget_test.dart` を全面置き換える（既存のカウンターテストは削除してよい。デフォルト生成物のため）。フェイク `BridgeService`（インメモリ実装）をProviderScopeでoverrideし、以下を検証する。
   - リスト一覧が表示される（フェイクデータ）
   - リストをタップ→タスク一覧画面へ遷移し、タスクが表示される
   - タスクをタップ→詳細画面へ遷移し、タイトルが表示される
   - リスト作成ダイアログ→入力→作成でフェイクserviceに反映され一覧が更新される
   - タスクのチェックでdone遷移がフェイクserviceに伝わる
   - ネイティブライブラリ・`initCore` に依存しないこと（`RustLib.init()` を呼ばない）
7. 既存の `app/test/rust_bridge_test.dart` / `app/test/core_usecases_test.dart` は変更しない（引き続き全部通ること）。

### やらないこと

- デザイン磨き込み・テーマ・ダークモード（`docs/07_Phase1計画書.md` M3/M4の範囲）。
- i18n（M2-04の範囲）。文字列は英語ハードコードでよいが、後でARB化しやすいよう画面ごとに散らかしすぎない程度の配慮に留める。
- ゴミ箱一覧画面・復元UI（M3の範囲）。
- サブタスク表示（M3の範囲）。
- 並び替えUI（M3の範囲）。
- fractional index本実装（M3の範囲。本タスクでは単純連番文字列のプレースホルダーで代替する）。
- `riverpod_generator` / `build_runner` の導入。
- 新規pubパッケージの追加（本タスクの実行環境はネットワークアクセス不可であるため、crates.io/pub.devからの新規取得が発生する変更を行ってはならない。追加済みの `flutter_riverpod` / `go_router` / `path_provider` のみ使用する）。
- `core/` および `app/rust/` の変更。
- FRB codegenの再実行（Rust API変更が無いため不要のはず。もし必要になったら理由を完了報告に記載する）。

## 5. 実装手順（例）

1. `docs/tasks/task-08-bridge-usecases.md`、`app/lib/main.dart`、`app/lib/src/rust/api.dart`、`app/test/rust_bridge_test.dart`、`app/test/core_usecases_test.dart`、`app/pubspec.yaml`、`docs/07_Phase1計画書.md` M2、`docs/02_機能仕様書.md` F-02 を再読し、既存のブリッジAPI・Dartテストの流儀・依存パッケージの状況を把握する。
2. `app/lib/src/core/bridge_service.dart` を新規作成し、抽象クラス `BridgeService` と実装 `FrbBridgeService` を実装する。
3. `app/lib/src/core/providers.dart` を新規作成し、`bridgeServiceProvider` / `listsProvider` / `tasksProvider` / `taskDetailProvider` とそれぞれのNotifierを実装する。
4. `app/lib/src/router.dart` を新規作成し、go_routerのルート定義を実装する。
5. `app/lib/src/screens/lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart` を新規作成し、各画面を実装する。
6. `app/lib/main.dart` を書き換え、`TaskveilApp` を分離しつつ `main()` でのネイティブ初期化とエラー画面表示を実装する。
7. `app/test/widget_test.dart` を全面置き換え、フェイク `BridgeService` を用いたwidget testを実装する。
8. `cd app && flutter analyze` と `cd app && flutter test` を実行して確認する。
9. 最後に `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行し、Rust側の回帰がないことを確認する（本タスクではRust側は変更しないため、既存の緑を維持するだけでよい）。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する（回帰確認）
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する（回帰確認）
- [ ] `cargo test --workspace` が全テスト成功する（回帰確認）
- [ ] `cd app && flutter analyze` が警告・エラーなしで完了する
- [ ] `cd app && flutter test` が全テスト成功する（新widget testを含む）
- [ ] widget testがネイティブライブラリ・`initCore` に依存しないこと（`RustLib.init()` を呼ばないこと）

## 7. 制約・注意事項

- Riverpod 3.x のAPI（`AsyncNotifier` / `AsyncNotifierProvider` / `Provider`）を使用する。2.x時代の `StateNotifier` は使わない。
- go_router 17.x のAPIを使用する。
- `docs/01〜04`・`docs/07_Phase1計画書.md` は変更しないこと。
- デスクトップ（macOS）で `flutter run -d macos` する場合の動作は必須検証項目ではない（widget testで担保できればよい）。
- 仕様書の記述だけでは一意に決まらない実装判断が生じた場合は、独断で仕様書側を変更せず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。

## 8. 完了報告に含めるべき内容

- 作成したファイル一覧と役割
- providerの構成（invalidate戦略を含む）
- ルート定義
- widget test数と検証内容
- 暫定sort_order生成の方式
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `app/lib/src/core/bridge_service.dart` を追加し、抽象クラス `BridgeService` とFRB生成APIをラップする実装 `FrbBridgeService` を実装した。widget testからネイティブライブラリ無しでフェイク実装に差し替えられるようにする目的である。
- `app/lib/src/core/providers.dart` を追加し、`bridgeServiceProvider` / `listsProvider`（`AsyncNotifierProvider`）/ `tasksProvider`（`AsyncNotifierProvider.family`、`listId` をキーとする）/ `taskDetailProvider`（`Provider.family`、`tasksProvider` の結果から導出）と、暫定sort_order生成ヘルパーを実装した。
- `app/lib/src/router.dart` を追加し、go_routerによる `/lists` → `/lists/:listId/tasks` → `/lists/:listId/tasks/:taskId` のルート定義を実装した。
- `app/lib/src/screens/lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart` を追加し、リスト一覧・タスク一覧・タスク詳細の3画面を実装した。
- `app/lib/main.dart` を書き換えた。`main()` で `RustLib.init()` → `getApplicationSupportDirectory()` 配下のディレクトリで `initCore` → `TaskveilApp` を起動する構成にした。`TaskveilApp` は `overrides` / `router` を注入可能にし、widget testからはネイティブ初期化なしで組み立てられるようにした。初期化失敗時はエラー画面を表示する。
- `app/test/widget_test.dart` を全面置き換え、インメモリのフェイク `BridgeService` を `ProviderScope` でoverrideするwidget testを5件実装した。

### 作成したファイル一覧と役割

- `app/lib/src/core/bridge_service.dart`: ブリッジ抽象層。`BridgeService`（抽象）/ `FrbBridgeService`（FRB実装）。
- `app/lib/src/core/providers.dart`: Riverpod providers（`bridgeServiceProvider` / `listsProvider` / `tasksProvider` / `taskDetailProvider`）と暫定sort_order生成ヘルパー。
- `app/lib/src/router.dart`: go_routerのルート定義（`buildAppRouter`）。
- `app/lib/src/screens/lists_screen.dart`: リスト一覧画面。
- `app/lib/src/screens/tasks_screen.dart`: タスク一覧画面。
- `app/lib/src/screens/task_detail_screen.dart`: タスク詳細画面。
- `app/lib/main.dart`（書き換え）: アプリ初期化（`RustLib.init` → `initCore`）と `TaskveilApp` の起動。
- `app/test/widget_test.dart`（全面置換）: フェイク `BridgeService` を用いたwidget test。

### providerの構成（invalidate戦略）

- 変更系操作（`createList` / `createTask` / `setStatus` / `trashTask`）はNotifierのメソッドとして実装し、ブリッジ呼び出し成功後に `ref.invalidateSelf()` で自身を再取得する。
- `taskDetailProvider` は専用のget-by-idブリッジAPIが存在しないため、`tasksProvider` の結果を `ref.watch` してクライアント側で該当タスクを検索する方針とした。単一のキャッシュを正とする発想であり、`tasksProvider` の更新に自動追随する。専用APIが後続で公開された場合に差し替え可能な構造としている。

### ルート定義

- `/lists`（初期表示、リスト一覧）
- `/lists/:listId/tasks`（指定リストのactiveタスク一覧）
- `/lists/:listId/tasks/:taskId`（タスク詳細）

### widget test数と検証内容

`app/test/widget_test.dart` に5件実装した（フェイク `BridgeService` をProviderScopeでoverride、`RustLib.init()` は呼ばない）。

- リスト一覧が表示される
- リストをタップ→タスク一覧画面へ遷移し、タスクが表示される
- タスクをタップ→詳細画面へ遷移し、タイトルが表示される
- リスト作成ダイアログ→入力→作成でフェイクserviceに反映され一覧が更新される
- タスクのチェックでdone遷移がフェイクserviceに伝わる

### 暫定sort_order生成の方式

- `'a$existingItemCount'` 形式の単純連番文字列（例: `a0`, `a1`, `a2`...）を生成するヘルパーを用いた。fractional index本実装はM3の範囲である。

### 検証

- `cargo fmt --all -- --check` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功（62件）。
- `cd app && flutter analyze` 成功。
- `cd app && flutter test` 全10件成功。
- 既存の `app/test/rust_bridge_test.dart` / `app/test/core_usecases_test.dart` は変更せず、引き続き成功することを確認した。

### 未解決事項

- macOSデスクトップでの `flutter run -d macos` の実行確認は本タスクでは未実施である。ネイティブdylibのmacOSビルド配線が未整備のため（M2の残作業）。
- ゴミ箱一覧・復元UIは未実装である（M3の範囲）。
- `generated_plugins.cmake` にpubパッケージ追加に由来する自動生成差分（jni関連）が含まれている。
