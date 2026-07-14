# Todori 開発プレイブック

標準・重要変更レーンの作業を、複数branch / worktreeでも一貫して進めるためのフェーズと完了条件を定める。レーン、work item形式、共通品質ゲートの詳細は [`README.md`](./README.md) を正本とする。

## 状態と正本

- 長期の進行方向とマイルストーン完了条件はPhase計画書、設計判断はADRを正本とする。
- 新形式work itemの状態は各 `work-<UUIDv7>-<slug>.md` のYAML front matter、実装契約と結果は本文、変更履歴はgit / CIを正本とする。
- `STATUS.md` と `BACKLOG.md` はUUIDv7 pilot中の移行案内とlegacy情報であり、新形式work itemの中央一覧として更新しない。
- statusは `backlog` / `active` / `blocked` / `done` / `cancelled` のいずれかとする。レビューと修正の間も `active` を維持する。
- public/private境界を守り、private詳細をpublic work itemや報告へ転記しない。

## レーン

- **軽量**: task文書なしで調査、局所修正、検証、コミットまで行う。独立検証は必須としない。
- **標準**: `lane: standard` のwork itemを作り、以下のフェーズと独立検証を通す。
- **重要変更**: `lane: critical` のwork itemを作り、標準に加えて人間承認を得る。未決の設計判断は実装前にADRまたは仕様へ記録する。

軽量作業でも、変更が複数層へ広がる、受け入れ基準が必要になる、同じ箇所で2回手戻りする、またはschema・FRB・暗号・鍵・新規依存・public/private境界へ触れる場合は昇格する。

## 作成と着手

IDは次のコマンドで生成する。コマンドはIDを1件表示するだけで、task文書、branch、worktree、commit、pushを作成しない。

```sh
cargo run -q -p todori-xtask -- work-id
```

- **将来候補を登録する**: 計画用branch / worktreeで `status: backlog` のwork itemを作り、実装前にmainへ取り込む。
- **作成と同時に着手する**: UUIDv7を生成し、そのIDを含むbranch / worktreeを作り、最初の変更として `status: active` のwork itemを作る。
- **main登録済み候補へ着手する**: 対象の `backlog` work itemのIDを含むbranch / worktreeを作り、`status: active` へ更新してから実装する。

branchは `work/<UUIDv7>-<slug>`、worktreeは `../todori-work-<UUIDv7先頭8桁>-<slug>` を標準とする。1 worktreeで扱うwork itemは原則1件とする。

## フェーズ

### 1. 調査・計画

仕様、既存実装、依存関係、リスクを調べ、work itemの1〜8章へスコープと受け入れ基準を統合する。指示書をレビューし、実装の分割単位と依存順序を決める。重要変更は必要な人間承認と設計記録を確認してから次へ進む。

### 2. 実装・統合

分割した範囲を実装し、統合したHEADで必要な品質ゲートを実行する。実装者は変更内容、検証事実、未解決事項を `## 9. 完了報告` へ記録するが、合否は判定しない。

### 3. レビュー・テスト

実装を担当していないエージェント、別セッション、または人間が、統合したHEADを独立検証する。受け入れ基準とリスクに応じた品質ゲートを再確認し、合格または不合格を再現可能な根拠とともに記録する。

### 4. 修正・再検証

不合格の場合だけ行う。具体的な指摘を修正し、統合したHEADを再び独立検証する。指摘がwork item契約や設計判断を変える場合は調査・計画へ戻り、それ以外は合格するまでこのフェーズを繰り返す。

## 並列化

各フェーズのエージェント数は固定しない。調査、実装、レビュー、修正は、分割可能なら並列化してよい。

- 担当範囲、編集するファイル、依存順序を先に分ける。
- 同一ファイルや同じ不変条件を複数エージェントが同時に変更しない。
- 共有interfaceやmigrationなどの前提を先に統合してから後続作業を広げる。
- 合否は個別成果ではなく、すべてを統合したHEADに対して判定する。

分割による調整コストが上回る場合は、エージェント数を増やす必要はない。サブエージェントを使わない場合も、実装記録と合否判定は分ける。

## 記録と完了

`## 9. 完了報告` は実装者だけの完了宣言ではなく、実装結果と独立検証を残す共同記録である。書式は [`README.md`](./README.md) に従い、CIログ全文、秘密情報、抽象的な品質評価語を貼らない。

次を満たした時点でwork itemを完了とする。

- 受け入れ基準を満たし、独立検証が合格している。
- front matterを `status: done` へ更新している。
- 意図しない未コミット差分やpublic/private境界違反がない。
- 実行不能、skip、環境制約がある場合は、コード失敗と区別できる事実を記録している。

完了時に `STATUS.md`、`BACKLOG.md`、READMEへ状態や完了一覧を同期しない。

## 候補管理

新しい候補は、Phase計画書の未達、完了work itemの未解決事項、ADR、ドッグフーディング結果、またはプロダクトオーナーの決定を出典として作る。新形式では候補登録時にUUIDv7と `status: backlog` のwork itemを作成し、連番や中央のNext一覧は使用しない。

UIの視覚作業では [`DESIGN_PLAYBOOK.md`](./DESIGN_PLAYBOOK.md) も使う。相談中の微調整は逐一task化しない。
