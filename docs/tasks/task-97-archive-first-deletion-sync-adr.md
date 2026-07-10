# task-97: Archive-first削除同期の再裁定

> ステータス: 完了（ADR-016と関連仕様をarchive-first削除同期へ再裁定）
> 作業日: 2026-07-11

## 1. 背景とコンテキスト

ADR-009は、完了済みtaskを振り返りのための記録資産とし、通常の整理は`done` / `wont_do`とリストのアーカイブ、永久削除はミス操作やノイズを本当に消す例外操作と定めている。一方、ADR-012の後続候補は、別端末の未知descendantをserverが即時拒否するためのaggregate scope / epochを要求し、server-visible metadataと同期protocolの複雑さを増やす方向へ進んでいた。

2026-07-11にプロダクトオーナーは、archive-firstの思想を企画書へ短く明記し、削除同期はserver-visibleなlist / parent / scope metadataを増やさず、180日tombstone、GC horizon、長期offline deviceのfull resync / rebaseで扱う方針を承認した。本taskはこの裁定をADRと技術仕様へ記録する。コード実装は後続taskとする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/STATUS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md` F-06 / F-07 / F-09
- `docs/03_技術仕様書.md` §6
- `docs/05_設計判断記録.md` ADR-009 / ADR-010 / ADR-012 / ADR-015
- `docs/tasks/task-95-fuzzy-scan-full-resync-gc-horizon.md`

## 3. ゴール

- archive-first、delete-exceptionという既存の製品思想を企画書へ短く明記する。
- aggregate scope / epochを導入せず、E2EE metadata最小化を維持する削除同期規約をADRとして確定する。
- tombstoneを永久保持せず、保持期間とoffline deviceの復帰保証期間を一致させる。
- GC horizonを超えた端末で、正当なoffline新規リストを失わず、削除済み既存entityを復活させないrebase分類を定義する。
- 現行ADR / 技術仕様 / STATUSの後続作業を新しい裁定へ同期する。

## 4. スコープ

### やること

- `docs/01_企画書.md`へarchive-firstの短い製品原則を追加する。
- ADR-016として、bounded tombstone、terminal deletion、server-enforced device continuity、expired-device rebase、client-side descendant cascadeを裁定する。
- ADR-010 / ADR-012 / ADR-015と`docs/03_技術仕様書.md`のaggregate scope / epoch前提を補正する。
- `STATUS.md`の次候補を、ADR-016を実装する後続taskへ置き換える。

### やらないこと

- Rust / Dart / Flutter / SQL migration / wire protocolの実装変更。
- tombstone保持期間180日の変更。
- task個別の`archived_at`機能追加。現行taskの保全経路は`done` / `wont_do`とする。
- Organization共有で悪意あるmemberをserverがscope単位に遮断する仕組み。Phase 3の脅威モデルで再評価する。
- private repoの変更。

## 5. 実装手順

1. ADR-009と企画書の記述差を確認し、企画書へ製品思想だけを短く追記する。
2. ADR-016へ削除同期の不変条件、offline期限、local-new / server-seen分類、dependency validation、List DEK保持条件を記録する。
3. ADR-010 / ADR-012 / ADR-015へADR-016による補正を追加する。
4. 技術仕様§6のlive/tombstone勝敗、sync順、full resync rebase、server push guard、aggregate削除記述を新裁定へ合わせる。
5. STATUSの次候補を新裁定の実装taskへ更新する。
6. 文書リンク、用語、矛盾、`git diff --check`を確認する。
7. 実装を担当していないエージェント、別セッション、または人間が独立検証する。

## 6. 受け入れ基準

- [x] 企画書が、タスクを記録資産として扱い、通常の整理を`done` / `wont_do` / archive、永久削除を例外と説明している。
- [x] ADR-016がaggregate scope / epochを採用しない理由と、server-visible metadataを増やさない境界を明記している。
- [x] tombstone保持期間とoffline復帰保証期間を180日として接続し、expired deviceはfull resync完了前にpushできない。
- [x] server-seen record、local-new record、offline edit、missing/deleted dependencyのrebase規則が区別されている。
- [x] 一度もserverへ存在しないoffline新規リストと、その配下のlocal-new taskは、durable origin / pending key bundle / dependency closureの検証後に再seedされ、absenceだけで削除されない。
- [x] serverに以前存在したがfull resync後に不在のrecordと、削除・不在の既存list / parent配下recordは再pushされない。
- [x] permanent delete後の同一record IDはliveへ復活せず、明示的な再作成は新IDを使う。
- [x] task/list内容とserver historyを削除し、tombstoneは最小metadataだけを保持する規則が維持されている。
- [x] ADR-010 / ADR-012 / ADR-015、技術仕様、STATUSがADR-016と矛盾しない。
- [x] コード、schema、wire protocolを変更していない。
- [x] `git diff --check`が成功し、独立検証が合格している。

## 7. 制約・注意事項

- `docs/01_企画書.md`の変更は、本taskへのプロダクトオーナー承認範囲に限定する。
- offline-firstである以上、接続していない端末を遠隔消去できるとは表現しない。次回sync時の収束保証を記述する。
- expired判定はlocal clockや申告cursorを信用せず、serverが保持するdevice continuity stateとprotocol versionで強制する。
- `base_revision=None`だけでlocal-newを断定せず、durableなserver-seen / local-origin状態、pending List DEK bundle、dependency closureを組み合わせる。
- archive dataの長期保全と、削除伝播用tombstoneの有限保持を混同しない。
- List DEK bundleは削除済み内容そのものではない。安全なretirement条件が実装されるまでは削除しない。

## 8. 完了報告に含めるべき内容

- 企画書へ追加した製品原則。
- ADR-016の主要裁定と、補正した既存ADR。
- offline新規リストが保持される条件と、削除済み既存entityが破棄される条件。
- 技術仕様 / STATUSの変更点。
- 独立検証結果、commit hash、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-11
- 結果: 企画書へarchive-first / delete-exception原則を追記し、ADR-016でbounded tombstone、terminal deletion、server-trusted device continuity、expired-device rebase、client-side late descendant cascade、List DEK retirement条件を裁定した。ADR-010 / ADR-012 / ADR-014 / ADR-015と技術仕様の旧復活規約・push順・GC後rebaseを補正した。
- 証拠: `git diff --check` 成功。差分は公開文書5ファイルのみで、Rust / Dart / Flutter / SQL migration / wire implementationの変更なし。
- Commit: `69a6664`
- 未解決: ADR-016の後続実装（terminal tombstone、history purge、pull-before-push、device continuity、expired rebase、late descendant cascade、List DEK retirement）。

### 独立検証

- 判定: 合格
- 根拠: 初回監査のADR-010残存矛盾、client提示cursor基準、current tombstone分類を修正し、再検証でP1 / P2 / P3なし。`git diff --check` 成功。
- 検証者: 実装を担当していない独立エージェント
