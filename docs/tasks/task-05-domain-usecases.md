# task-05: `core/domain` へのリスト/タスクユースケース追加

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM1「コア層完成」は、M1-01「`core/domain` にリスト/タスク操作ユースケースを追加する」を最初のタスクとして定義している。このタスクはM1-01に対応する。

`core/domain` はTaskveilのRust workspaceの中で、ストレージ（`core/storage`、rusqlite/SQLCipher）にもFlutterブリッジにも依存しない**純粋ロジックcrate**である。現時点では `core/domain/src/entities.rs` に `Task` / `List` / `TaskStatus` エンティティと `TaskStatus::can_transition_to` のみが実装されており、タスク・リストを生成／編集／状態遷移させるユースケース関数は未実装である。

リポジトリ（`core/storage` 側のDB接続）とユースケースを結びつける作業はM1-03（別タスク）で行う。したがって本タスクでは、DBにもファイルシステムにもアクセスしない、**値を受け取り値を返す純粋関数・メソッド**としてユースケースを実装する。「現在時刻」はテスト可能性のため呼び出し側から `now_ms: i64`（UTC epoch milliseconds）として明示的に注入すること。システムクロックを内部で読み取るコード（`SystemTime::now()` 等）を追加しないこと。

## 2. 事前に読むべきファイル

- `docs/02_機能仕様書.md` F-05（タスクのCRUD）、F-06（ステータス遷移とサブタスク）、F-07（ゴミ箱・Undo）
- `docs/03_技術仕様書.md` §3.5（lists）、§3.6（tasks。特に `completed_at` / `closed_reason` / `deleted_at` の意味論の説明文）
- `core/domain/src/entities.rs`（`Task` / `List` / `TaskStatus` の現状。`TaskStatus::can_transition_to` の許可遷移一覧）
- `core/domain/src/lib.rs`（crateのエントリポイント、re-exportの現状）
- `docs/07_Phase1計画書.md` M1（本タスクが対応するM1-01と、後続のM1-03がどこまでを担うかの切り分け）

## 3. ゴール

`core/domain` に `usecases` モジュールを新規追加し、リスト・タスクの生成/編集/ステータス遷移/論理削除・復元/親子関係検証を行う純粋関数・メソッド群を実装する。すべて単体テストで正常系・異常系が検証され、`cargo test --workspace` で緑になること。

## 4. スコープ

### やること

`core/domain/src/usecases.rs`（新規ファイル）に以下を実装し、`core/domain/src/lib.rs` に `pub mod usecases;` を追加、主要な公開型（エラー型・ユースケース関数群）を既存の `entities` re-exportに倣ってre-exportする。

1. **タスク生成**: `new_task(list_id: Uuid, parent_task_id: Option<Uuid>, title: String, sort_order: String, now_ms: i64) -> Result<Task, DomainError>` を実装する。`id` は `Uuid::now_v7()`、`status` は `TaskStatus::Todo`、`created_at` / `updated_at` は `now_ms`、その他のフィールド（`note` は空文字列、`priority` は `0`、`due_at` / `scheduled_at` / `estimated_minutes` / `completed_at` / `closed_reason` / `deleted_at` / `assignee` は `None`）は適切なデフォルト値とする。`title` が空文字列（トリム後に空、を含めるかは実装者の判断でよいが方針をコード上コメントで明記する）の場合は `DomainError::EmptyTitle` を返す。

2. **タスク編集**: `title` / `note` / `priority` / `due_at` / `scheduled_at` / `estimated_minutes` を更新する関数群（例: `update_title`, `update_note`, `update_priority`, `update_due_at`, `update_scheduled_at`, `update_estimated_minutes` など、既存タスクの命名スタイルに沿った適切な粒度でよい）を実装する。いずれも更新に成功した場合は `updated_at` を `now_ms` に更新する。`title` を空文字列に変更しようとした場合は `DomainError::EmptyTitle` を返し、タスクは変更されない。

3. **ステータス遷移ユースケース**: `transition_task(task: Task, next: TaskStatus, closed_reason: Option<String>, now_ms: i64) -> Result<Task, DomainError>` を実装する。既存の `TaskStatus::can_transition_to` をそのまま利用し、遷移が許可されない場合は `DomainError::InvalidTransition` を返す（`TaskStatus::can_transition_to` 自体のシグネチャ・ロジックは変更しないこと）。遷移が許可される場合の意味論は以下の通りとする。
   - `Done` への遷移: `completed_at = Some(now_ms)`、`closed_reason = None` とする（`docs/03_技術仕様書.md` §3.6 の `closed_reason` 説明「done / wont_do 時の理由」は理由欄が両方で使われうることを示すが、本タスクでは `Done` は「完了日時」の記録を主とし `closed_reason` は使わない実装とする。異なる解釈を採る場合はコード上に理由をコメントし、完了報告にも記載すること）。
   - `WontDo` への遷移: `completed_at = None`（`completed_at` は「完了日時」であり `wont_do` は完了ではないため設定しない、という解釈を採る。F-06に明記された「`wont_do` は完了扱いにはせず区別して記録する」という記述を根拠とする）、`closed_reason` は引数の値をそのまま設定する（`None` も許容する）。
   - `Todo` への再オープン（`Done`/`InProgress` からの遷移）: `completed_at = None`、`closed_reason = None` にクリアする。
   - `InProgress` への遷移: `completed_at` / `closed_reason` は変更しない（`None` のまま）。
   - いずれの遷移でも成功時は `status = next`、`updated_at = now_ms` とする。
   - 上記の解釈は仕様書の記述から演繹される合理的解釈であり、確定仕様ではない。曖昧さが残る場合は独断で仕様書を書き換えず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。

4. **論理削除・復元（F-07 ゴミ箱・Undo）**: `delete_task(task: Task, now_ms: i64) -> Result<Task, DomainError>` で `deleted_at = Some(now_ms)` を設定する（物理削除は行わない。30日後の完全削除バッチはPhase 1の別タスクの範囲であり本タスクでは扱わない）。`restore_task(task: Task, now_ms: i64) -> Result<Task, DomainError>` で `deleted_at = None` に戻し `updated_at = now_ms` とする。既に `deleted_at` が設定済みのタスクに対して2.の編集系関数や3.の `transition_task` を呼び出した場合は `DomainError::TaskDeleted` を返す。`delete_task` を既に削除済みのタスクへ呼んだ場合、および `restore_task` を削除されていないタスクへ呼んだ場合の挙動も定義し（エラーにするか冪等に成功させるかは実装者の判断でよいが、方針をコード上のコメントと完了報告に明記すること）、対応するテストを書く。

5. **サブタスク制約の検証**: `validate_parent(task: &Task, candidate_parent_id: Uuid, tasks: &[Task]) -> Result<(), DomainError>`（または同等のシグネチャ。`task` 自身がまだ存在しない新規作成時にも使えるよう、対象タスクIDと親候補IDを分離した設計にしてよい）を実装し、以下を検証する。
   - (a) 自己参照禁止: `candidate_parent_id` が対象タスク自身のIDと一致する場合はエラー（例: `DomainError::SelfReferenceParent`）。
   - (b) 親の存在確認: `candidate_parent_id` が `tasks` 内に存在しない場合はエラー（例: `DomainError::ParentNotFound`）。
   - (c) リスト一致: 親候補の `list_id` が対象タスクの `list_id` と異なる場合はエラー（例: `DomainError::ParentInDifferentList`）。
   - (d) 循環禁止: 親候補の祖先チェーンを `parent_task_id` を辿って走査し、対象タスク自身に戻る（循環になる）場合はエラー（例: `DomainError::CyclicParent`）。
   - (e) 削除済み禁止: 親候補の `deleted_at` が `Some` の場合はエラー（例: `DomainError::ParentDeleted`）。
   - エラー型は用途ごとに区別できるバリアントとすること（1つの汎用エラーに丸めない）。

6. **リスト操作**: `new_list(name: String, sort_order: String, now_ms: i64) -> Result<List, DomainError>`（`id` は `Uuid::now_v7()`、`color`/`icon` は適切なデフォルト値、`org_id` は `None`、`created_at`/`updated_at` は `now_ms`。`name` が空文字列の場合は `DomainError::EmptyName` を返す）、および `rename_list` など名称変更の更新関数（成功時 `updated_at` を更新、空文字列への変更はエラー）を実装する。

7. **エラー型**: `DomainError`（`thiserror::Error` を用いる。`core/domain` は既に `thiserror` に依存しているため新規依存追加は不要）を定義し、上記すべてのエラーケースをバリアントとして表現する。

8. **単体テスト**: 上記1〜6のすべてについて正常系・異常系のテストを書く。少なくとも以下を含めること。
   - 空titleでの `new_task` / 編集失敗
   - 空nameでの `new_list` / 名称変更失敗
   - `can_transition_to` が許可しない遷移を `transition_task` に渡した場合のエラー
   - `Done` / `WontDo` / 再オープンそれぞれの遷移後の `completed_at` / `closed_reason` の値
   - 削除済みタスクへの編集・遷移試行のエラー
   - 削除・復元の正常系
   - 自己参照parentのエラー
   - 循環parent（例: A→B→C→A のような間接循環）のエラー
   - 別リストparentのエラー
   - 削除済みタスクをparentにしようとした場合のエラー
   - 存在しないparentを指定した場合のエラー

### やらないこと

- `core/storage` / `core/crypto` / `core/sync` / `app/` / `cli` / `mcp-server` / `server` の変更。
- リポジトリtrait（DB永続化層とのインターフェース）の定義・接続。これはM1-03のスコープである。
- fractional index（`sort_order`）の生成・再計算アルゴリズムの実装。本タスクのユースケースは呼び出し側が計算済みの `sort_order: String` を渡す前提とし、文字列としてそのまま格納する（fractional indexアルゴリズムはPhase1計画書M3で扱う）。
- タスクの30日後物理削除バッチ、Undoスタック（操作履歴）の実装。本タスクは論理削除フラグの単純な設定・解除のみを行う。
- 新規外部依存クレートの追加。特に**ネットワークアクセスを要する新規クレートの追加は禁止**する。`thiserror` は既存依存を再利用すること。
- `docs/01〜04` および `docs/07_Phase1計画書.md` の変更。

## 5. 実装手順（例）

1. `core/domain/src/entities.rs` を再読し、`Task` / `List` / `TaskStatus` の全フィールドと `can_transition_to` の遷移表を正確に把握する。
2. `core/domain/src/usecases.rs` を新規作成し、まず `DomainError` enum（`thiserror::Error` 実装）を定義する。
3. `new_task` / `new_list` とその異常系テストを実装する。
4. タスク・リストの編集系関数とテストを実装する。
5. `transition_task` を実装する。`Done` / `WontDo` / 再オープン / `InProgress` の各ケースで `completed_at` / `closed_reason` がどうなるかをテストで固定する。
6. `delete_task` / `restore_task` と、削除済みタスクへの編集・遷移がエラーになることのテストを実装する。
7. `validate_parent` を実装する。祖先チェーン走査のロジックは無限ループに陥らないよう、`tasks` スライスから `parent_task_id` を辿るヘルパーを別関数として切り出すとよい。
8. `core/domain/src/lib.rs` に `pub mod usecases;` を追加し、必要な型をre-exportする。
9. `cargo test -p taskveil-domain` を繰り返し実行しながら実装する。
10. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行し全体の品質ゲートを確認する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する
- [ ] `cargo test --workspace` が全テスト成功する（既存の `entities.rs` のテストも含めすべて成功すること）
- [ ] `cargo test -p taskveil-domain` で本タスクの新規テストがすべて実行され成功する
- [ ] 4.の8.に列挙した異常系テスト（空title/空name、不許可遷移、削除済みタスクへの編集・遷移、自己参照parent、循環parent、別リストparent、削除済みparent、存在しないparent）がすべて実装され成功する

## 7. 制約・注意事項

- 既存の `core/domain/src/entities.rs` の公開API（`Task` / `List` / `TaskStatus` のフィールド構成、`TaskStatus::can_transition_to` のシグネチャと挙動）を変更・破壊しないこと。既存テストがすべて通ることを維持する。
- 現在時刻をコード内で直接取得しないこと（`now_ms` は必ず引数として受け取る）。
- 仕様書（`docs/02_機能仕様書.md` / `docs/03_技術仕様書.md`）の記述だけでは一意に決まらない意味論（特に3.の `Done`/`WontDo` 遷移時の `completed_at`/`closed_reason` の扱い）については、本指示書が示す解釈をデフォルトの実装方針とすること。それでもなお判断に迷う点が生じた場合は、独断で仕様書側を変更せず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/04_課金設計書.md` は変更しないこと。

## 8. 完了報告に含めるべき内容

- 追加した公開API（関数・メソッド・型）の一覧
- `WontDo` 遷移時の `completed_at` / `closed_reason` の扱いについて採用した解釈と、その根拠
- `Done` 遷移時に `closed_reason` を用いるかどうかについて採用した解釈と、その根拠
- 追加した単体テストの総数と、4.の8.に列挙した異常系テストがすべて含まれていることの確認
- 削除済みタスクへの `delete_task` 再呼び出し、未削除タスクへの `restore_task` 呼び出しの挙動として採用した方針
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `core/domain/src/usecases.rs` を追加し、`core/domain/src/lib.rs` から `pub mod usecases;` と主要APIのre-exportを追加した。
- 追加した公開型は `DomainError`。
- 追加した公開関数は `new_task` / `new_list` / `update_title` / `update_note` / `update_priority` / `update_due_at` / `update_scheduled_at` / `update_estimated_minutes` / `transition_task` / `delete_task` / `restore_task` / `rename_list` / `validate_parent` / `validate_parent_for`。
- `title` / `name` は `trim()` 後に空の場合も未入力として `DomainError::EmptyTitle` / `DomainError::EmptyName` を返す方針にした。
- `delete_task` は論理削除のみを行い、物理削除や30日後削除バッチ、Undoスタックは本タスクの範囲外として扱った。

### ステータス遷移の解釈

- `WontDo` への遷移では `completed_at = None`、`closed_reason = 引数値` とした。F-06の「`wont_do` は完了扱いにはせず区別して記録する」という記述に合わせ、完了日時は設定しない。
- `Done` への遷移では `completed_at = Some(now_ms)`、`closed_reason = None` とした。本タスク指示の解釈どおり、`Done` は完了日時の記録を主とし、理由欄は使用しない。
- `Todo` への再オープンでは `completed_at` / `closed_reason` をどちらもクリアし、`InProgress` への遷移では完了関連メタデータを変更しない。

### 削除・復元の方針

- 削除済みタスクへの編集系関数および `transition_task` は `DomainError::TaskDeleted` を返す。
- 削除済みタスクへの `delete_task` 再呼び出しは、リトライを安全にするため冪等に成功させる。既存の `deleted_at` / `updated_at` は変更しない。
- 未削除タスクへの `restore_task` 呼び出しも冪等に成功させる。`deleted_at` / `updated_at` は変更しない。

### テスト

- `core/domain/src/usecases.rs` に単体テストを25件追加した。
- 4.の8.に列挙された異常系は、空titleでの `new_task` / 編集失敗、空nameでの `new_list` / 名称変更失敗、不許可遷移、削除済みタスクへの編集・遷移、自己参照parent、間接循環parent、別リストparent、削除済みparent、存在しないparentをすべて含めた。
- 正常系は、タスク/リスト生成、タスク各フィールド更新、`Done` / `WontDo` / 再オープン / `InProgress` 遷移、削除・復元、親検証成功、新規作成時向けの `validate_parent_for` を含めた。

### 検証

- `cargo test -p taskveil-domain` 成功。
- `cargo fmt --all -- --check` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功。

### 未解決事項

- なし。
