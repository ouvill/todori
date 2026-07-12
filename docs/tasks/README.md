# docs/tasks ── Todoriの実装作業

このディレクトリは、実装へ昇格した作業の指示書と完了証拠を置く。候補段階ではtask文書を作らず、現在と次候補は [`STATUS.md`](./STATUS.md)、Next以外の未着手候補は [`BACKLOG.md`](./BACKLOG.md) で管理する。

既存の `task-01`〜`task-107` は履歴としてそのまま保持する。完了タスクの一覧や状態をREADME / BACKLOGへ重複転記しない。必要な履歴はtaskファイル、git log、Phase計画書から確認する。

## 作業開始時の読む順

1. リポジトリルートの [`AGENTS.md`](../../AGENTS.md)
2. [`STATUS.md`](./STATUS.md)
3. [`PLAYBOOK.md`](./PLAYBOOK.md)（標準・重要変更レーン、またはオーケストレーション時）
4. 対象の `task-NN-*.md`（昇格済みの場合）
5. 対応する仕様書、Phase計画書、ADR

## 3つの作業レーン

| レーン | task文書 | 対象 |
|---|---|---|
| 軽量 | 不要 | 小さなバグ、文言、リンク、既存仕様内の局所修正、読み取り調査 |
| 標準 | task + 独立検証 | 新機能、複数層の変更、半日級以上、固有の受け入れ基準が必要な変更 |
| 重要変更 | task + 人間承認 + 独立検証 | 暗号、鍵、同期プロトコル、DB schema、依存追加、public/private境界、データ損失リスク。未決の設計判断はADRまたは仕様へ記録する |

判定は行数よりリスクを優先する。軽量レーンでも変更が広がった、同じ箇所で2回手戻りした、受け入れ条件が曖昧になった場合は標準レーンへ昇格する。

## taskへの昇格

- BACKLOGへ入っただけではtask番号を振らない。
- `STATUS.md` のNext候補から着手を決めた時点でtask番号を採番する。
- 標準taskは原則として次の章を持つ。
  1. 背景とコンテキスト
  2. 事前に読むべきファイル
  3. ゴール
  4. スコープ（やること / やらないこと）
  5. 実装手順
  6. 受け入れ基準
  7. 制約・注意事項
  8. 完了報告に含めるべき内容
- `## 9. 完了報告` は実装・統合後に追加し、独立検証結果を追記して共同完成させる。
- 候補を `STATUS.md` のNextへ移す時にBACKLOGから削除する。READMEへ完了行を追加しない。

## 共通規約

- public repoへprivate詳細（課金、収益、法務、監査、公開前ロードマップ）を転記しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` の変更は人間承認を必要とする。
- `docs/03_技術仕様書.md` は技術的な唯一の真実源であり、変更時は外科的差分と日付・ADR参照を維持する。
- 新規Rust依存はルート `Cargo.toml` の `[workspace.dependencies]` へ集約する。
- Flutter UI文字列はARB化する。
- FRB生成物は手編集しない。
- 秘密情報、Device Key、導出鍵、session token、復号済みplaintextをログや報告へ含めない。
- Conventional Commitsを使用する。

## 共通受け入れ基準

変更範囲に該当するものを実行する。task固有の基準には、テスト、スクリーンショット、計測値、ログ等の観測可能な証拠を1つ以上含める。

- [ ] `cargo fmt --all -- --check`
- [ ] `cargo clippy --workspace -- -D warnings`
- [ ] `cargo test --workspace`
- [ ] `cd app && flutter analyze`（Flutter変更時）
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後 `cd app && flutter test`（Flutter変更時）
- [ ] `sh app/tool/check_hardcoded_strings.sh`（Flutter変更時）
- [ ] `sh app/tool/check_client_boundaries.sh`
- [ ] `sh app/tool/test_client_boundaries.sh`
- [ ] `git diff --check`
- [ ] ARB変更時に `flutter gen-l10n` を実行し、生成物を手編集していない
- [ ] UI変更時にtooltip / semantics、タップ領域、色以外の情報伝達を維持している
- [ ] public/private境界と対象taskの変更禁止範囲を守っている
- [ ] `## 9. 完了報告` に実装結果と独立検証結果を記録している（taskレーンのみ）

## 完了報告の規約

完了報告は履歴の要約であり、CIログの複製場所ではない。次を短く記録する。

```md
## 9. 完了報告

### 実装結果

- 作業日: YYYY-MM-DD
- 結果: 何が動くようになったか
- 証拠: テスト名、スクリーンショット、計測値
- Commit: <commit hash。未コミットなら「未コミット」>
- 未解決: なし、または後続候補の要約

### 独立検証

- 判定: 合格 / 不合格
- 根拠: 再実行した品質ゲートと指摘
- 検証者: 実装を担当していないエージェント、別セッション、または人間
```

実装者は実装結果へ事実だけを記録し、合否を自己判定しない。全品質ゲートが通常どおり成功した場合はコマンド名と「成功」だけでよい。失敗、skip、環境制約、通常と異なる検証条件は再現可能な詳細を残す。

独立検証の合格後にtask冒頭へ次を置く。taskファイルが完了状態の正本である。

```md
> ステータス: 完了（短い結果）
> 作業日: YYYY-MM-DD
```

## 履歴の探し方

```sh
rg --files docs/tasks -g 'task-*.md'
rg -n '^> ステータス:|^## 9\. 完了報告' docs/tasks/task-*.md
git log --oneline -- docs/tasks
```

手動の全task一覧は維持しない。完了履歴を集計する必要が生じた場合は、task冒頭の状態から生成する。
