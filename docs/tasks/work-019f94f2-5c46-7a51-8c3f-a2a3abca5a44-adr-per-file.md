---
id: 019f94f2-5c46-7a51-8c3f-a2a3abca5a44
title: Split architecture decision records into per-ADR files
status: done
lane: standard
milestone: maintenance
---

# Split architecture decision records into per-ADR files

## 1. 背景とコンテキスト

`docs/05_設計判断記録.md` はADR-001〜ADR-024を単一ファイルに保持し、1,000行を超えている。ADR追加時の差分競合、個別判断への直接リンク、履歴追跡を改善するため、1 ADR 1ファイルへ分割する。

既存文書から `docs/05_設計判断記録.md` への参照が多数あるため、同ファイルは削除せず互換索引として維持する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/05_設計判断記録.md`
- `README.md`
- `docs/03_技術仕様書.md`

## 3. ゴール

ADR-001〜ADR-024を個別ファイルへ機械的に分割し、既存参照を壊さない索引、将来の追加規約、機械検証を整備する。

## 4. スコープ

### やること

- `docs/adr/` にADR-001〜ADR-024を1件1ファイルで配置する。
- `docs/05_設計判断記録.md` を既存見出しanchorを維持した索引へ変更する。
- 各ADRのID、タイトル、日付、状態、本文を意味変更なく保持する。
- `AGENTS.md`、`README.md`、tasks運用文書へ新しい正本と追加規約を反映する。
- ADR件数、ID一意性、索引との一致、相対リンクを検証する。

### やらないこと

- 既存ADRの判断内容、番号、状態を変更しない。
- ADRを分野別に再採番しない。
- 過去task文書の参照を一括置換しない。
- public/private境界や技術仕様を変更しない。

## 5. 実装手順

1. ADR見出し単位で既存本文を個別ファイルへ移す。
2. 旧ファイルをID順の互換索引へ置き換える。
3. ADR追加・更新規約と機械検証を追加する。
4. 参照元とリンクを検査し、文書品質ゲートを実行する。

## 6. 受け入れ基準

- [x] ADR-001〜ADR-024が `docs/adr/` に1件1ファイルで存在する。
- [x] 個別ファイルの本文が分割前の各ADR本文と意味上同一である。
- [x] `docs/05_設計判断記録.md` の既存ADR見出しanchorとパスが維持される。
- [x] ADRのID、タイトル、日付、状態が索引と個別ファイルで一致する。
- [x] 新規ADRのファイル名、状態、索引更新規約が文書化される。
- [x] 並行branchで新規ADR番号が競合した場合の確定・再採番規約が文書化される。
- [x] repository内の相対Markdown link、ADR構造検査、`git diff --check`が成功する。
- [x] 実装を担当していない検証者または別セッションの独立検証が合格する。

## 7. 制約・注意事項

- 分割と判断内容の編集を同じ変更に混在させない。
- `docs/05_設計判断記録.md ADR-NNN` という既存の非リンク参照を有効な案内として残す。
- 既存ADRの内部相互参照はID表記を維持する。
- public repoへprivate詳細を追加しない。

## 8. 完了報告に含めるべき内容

- 作成した個別ADRと互換索引の構造
- 本文保持の検証方法
- 更新した運用規約
- リンク、構造、品質ゲートの結果
- 独立検証の判定と未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-25
- 結果: ADR-001〜ADR-024を `docs/adr/ADR-NNN.md` の個別正本へ分割し、`docs/05_設計判断記録.md` を既存パスと見出しanchorを維持する互換索引へ変更した。
- 結果: 1 ADR 1ファイル、3桁連番、状態遷移、採用済み判断の置換規約を索引、`AGENTS.md`、task運用文書へ記録した。
- 結果: 新規ADR番号は作業branch上では暫定とし、merge前に対象branchの最新状態を取り込み、競合時は個別ファイル、索引、参照を次の空き番号へ変更する規約を追加した。ADR IDは可読性を優先して3桁連番を維持する。
- 結果: `tool/check_adr_structure.sh` を追加し、ID一意性、連番、索引と個別ファイルの集合、タイトル、日付、状態、リンクを検証するCI jobを追加した。
- 証拠: 分割前のGit上の単一ファイルと24個の個別ファイルを機械比較し、見出しレベル以外がbyte-for-byteで一致した。
- 証拠: `sh tool/check_adr_structure.sh`、変更対象30 Markdownファイルの相対link検査、`actionlint .github/workflows/ci.yml`、`shellcheck tool/check_adr_structure.sh`、`sh tool/check_secret_patterns.sh`、`sh tool/ci/test_classify_changes.sh`、`cargo fmt --all -- --check`、`git diff --check`: PASS。
- Commit: 未コミット
- 未解決: なし。判断内容、技術仕様、public/private境界の変更はない。

### 独立検証

- 判定: 合格
- 根拠: 実装を担当していないサブエージェントが、全24本文の分割前HEAD比較、旧見出しanchor、metadata、相対link、CI実行条件、運用規約、public/private境界と品質ゲートを再確認した。初回レビューでADR構造checkerが入力欠損時に0件を成功扱いするfail-openを検出したため、索引・directory存在確認、pipeline廃止、ファイル名、最低24件、連番検査を追加した。再検証では正常24件が成功し、索引欠損、directory欠損、空入力、ADR-024欠損、不正filename、空索引の6負例がすべて非0で拒否された。並行branchの暫定採番規約を追加した後も、索引、`AGENTS.md`、task運用文書間の一貫性とcheckerとの整合を独立再レビューし、新規findingなし。
- 検証者: 実装を担当していないサブエージェント
