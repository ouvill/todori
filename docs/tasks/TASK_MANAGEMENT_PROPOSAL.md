# 並行開発に対応するタスク管理案

> ステータス: pilot採用
> 採用日: 2026-07-14

## 1. 方針

新規taskは連番を使わず、ローカルで生成したUUIDv7を正本IDにする。taskは1件1 Markdownファイルとし、状態はYAML front matterへ記録する。

- GitHub / GitLab等のtrackerを正本にしない。
- 既存のPhase計画書をプロジェクト方向の正本として維持する。
- `STATUS.md` / `BACKLOG.md` に新形式taskの状態を重複転記しない。
- 既存の `task-01`〜`task-108` は履歴として凍結し、改名・再採番しない。
- 新規の連番taskは作らない。

## 2. 解決する問題

同じmainから複数branch / worktreeを作ると、各branchが同じ「次のtask番号」を選べる。着手・完了のたびに中央の一覧を更新する方式も、実装範囲が独立している作業同士を管理文書上で競合させる。

UUIDv7と1タスク1ファイルにより、採番と中央一覧の競合をなくす。UUIDv7は時系列で概ね整列でき、既存workspaceの `uuid` crateで生成できるため、新しいexternal dependencyを必要としない。

## 3. task文書

新規taskのfilenameは次の形式にする。

```text
docs/tasks/work-<UUIDv7>-<slug>.md
```

例:

```text
docs/tasks/work-019f6116-8c37-78a2-9ba3-06c03d2a3ea0-canonical-inbox-convergence.md
```

front matterは必要最小限にする。

```yaml
---
id: 019f6116-8c37-78a2-9ba3-06c03d2a3ea0
title: Canonical Inbox convergence
status: backlog
lane: critical
milestone: maintenance
---
```

- `status`: `backlog` / `active` / `blocked` / `done` / `cancelled`
- `lane`: `standard` / `critical`
- `milestone`: Phase計画書のID。該当しない保守作業は `maintenance`

軽量レーンは従来どおりtask文書を必須にしない。本文は既存の1〜9章形式を維持し、独立検証が合格するまでは `active`、完了後は `done` とする。

## 4. ID生成

developer interfaceは次の1コマンドだけとする。

```sh
cargo run -q -p todori-xtask -- work-id
```

lowercase・hyphenated UUIDv7を1件だけ標準出力する。task文書、branch、worktree、commit、pushは作成しない。YAML parser、front matter validator、状態一覧generator、remote branch集計はpilotへ追加しない。

## 5. taskの作成と着手

UUIDv7を生成しただけではtask作成としない。UUIDv7入りtask文書を保存した時点をtask作成とする。

### 将来候補を登録する場合

計画用branch / worktreeでUUIDv7と `backlog` のtask文書を作り、実装前にmainへmergeする。

### 作成と同時に着手する場合

1. UUIDv7を生成する。
2. UUIDv7を含むbranch / worktreeを作る。
3. そのworktreeへ `active` のtask文書を最初に作る。
4. task文書を実装と一緒にmainへmergeする。

### 既存候補へ着手する場合

main上の `backlog` taskからbranch / worktreeを作り、そのworktreeで `status: active` へ更新してから実装する。

## 6. branch / worktree

branchとworktreeはUUIDv7を含む名前にする。

```text
branch:   work/019f6116-8c37-78a2-9ba3-06c03d2a3ea0-canonical-inbox
worktree: ../todori-work-019f6116-canonical-inbox
```

1 worktreeでは原則1件のwork itemを扱う。同じファイルや設計上の不変条件を変更する作業は、通常の実装計画で統合順を決める。

## 7. 状態とプロジェクト進行

プロジェクト方向と完了条件は既存のPhase計画書を正本とする。taskはfront matterの `milestone` で対応する計画項目へ紐づける。taskの状態はfront matter、結果は本文とgitを正本とし、生成した中央一覧はcommitしない。

レビューと修正の間は `active` を維持する。完了時に中央一覧を同期せず、独立検証の合格後に対象ファイルだけを `done` へ更新する。

## 8. pilot範囲

初回pilotは、2026-07-14時点で `STATUS.md` のNextだった次の2件だけを `backlog` の新形式へ移す。

- Canonical Inbox収束
- SQLCipherクロスビルドCI

Later、Quick fixes、Icebox、人間作業は移行しない。既存の進捗スナップショットもpilot中は維持する。pilot合格後の全面移行、`STATUS.md` / `BACKLOG.md` の廃止判断、追加automationは別work itemで扱う。

既存のpublic / private境界、Phase計画書、ADR、独立検証、完了報告、品質ゲートは変更しない。
