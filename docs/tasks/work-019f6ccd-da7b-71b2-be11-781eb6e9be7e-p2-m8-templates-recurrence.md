---
id: 019f6ccd-da7b-71b2-be11-781eb6e9be7e
title: P2-M8 templates and recurring tasks
status: done
lane: critical
milestone: P2-M8
---

# P2-M8 テンプレート・繰り返しタスク

## 1. 背景とコンテキスト

Phase 2 M8では、タスクsubtreeを再利用できるテンプレートと、RRULEに従って端末内でタスクを生成する繰り返し予定を実装する。Todoriはlocal-firstかつE2EEを維持するため、serverは生成処理、平文のテンプレート内容、平文の予定を扱わない。

本作業はlocal schema、sync protocol、新規Rust依存、FRB、Flutter UIへまたがる重要変更である。プロダクトオーナーは2026-07-17に本work itemの契約、critical変更、`rrule = 0.14.0`追加を承認した。実装前の設計判断はADR-021を正本とする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/README.md`
- `docs/02_機能仕様書.md` のF19〜F21
- `docs/03_技術仕様書.md` のテンプレート・繰り返し・同期仕様
- `docs/05_設計判断記録.md` のADR-007、ADR-015、ADR-016、ADR-021
- `core/domain`、`core/storage`、`core/sync`、`core/client`、`server`、`app/rust`、`app/lib`

## 3. ゴール

1. 任意の既存task subtreeを、再利用可能なcontent-only snapshotとして保存・置換・起票できる。
2. 検証済みRRULEから予定回を端末内で生成し、offline期間を上限なく補完できる。
3. 複数端末、再実行、full resyncでも同じ予定回のtask treeが重複しない。
4. templateとscheduleをTenant Root DEKでE2EE同期し、serverを平文・生成ロジックから分離する。
5. Lists画面から英日対応のTemplates管理画面へ移動し、起票、編集、schedule管理、控えめなstreak確認ができる。

## 4. スコープ

### やること

- `Template`に名前、既定list、snapshot revision、作成・更新日時を持たせる。snapshotは最大100 node・canonical JSON 49,152 UTF-8 bytesとし、安定node key、親node key、順序、title、note、priority、estimated minutesだけを保存する。
- `Schedule`にtemplate ID、正規化RRULE、開始instant、IANA timezone、nullableな次回発生instant、enabled、config revision、作成・更新日時を持たせる。
- `rrule = 0.14.0`をworkspace依存に追加し、DAILY/WEEKLY/MONTHLY/YEARLY、INTERVAL、BYDAY、BYMONTHDAY、COUNT、UNTILだけをv1で受理する。crateの検証上限を常時有効にする。
- local schema v20とsync protocol v6を導入し、`templates`と`schedules` collection、taskの内部recurrence provenanceを追加する。
- schedule ID、schedule revision、template revision、occurrence instant、snapshot node keyからUUIDv5でtask IDを決定する。手動起票はUUIDv7を維持する。
- 同一schedule revisionのcursorを単調増加でmergeし、1 occurrenceのtree生成とcursor更新を1 transactionで確定する。
- settlementを起動、foreground復帰、sync pull後に実行する。1回最大100 occurrenceでyieldしながら全件補完し、outbox増加時は既存single-flight syncへ再実行を要求する。
- template / schedule CRUD、subtree snapshot保存・置換、手動起票、settlement、streak取得を`TodoriClient`へ追加し、FRBをtyped DTO変換と委譲に限定する。
- Lists画面のTemplates導線、`/templates`画面、task詳細の保存操作、presetと詳細RRULE入力、停止・削除確認、英日ARB、semantics、390 px / text scale 2.0対応を実装する。
- server collection制約、stable cursor、full-resync制約を拡張し、既存head、cursor、tombstone、quarantineを保持する。
- template snapshotとschedule configをそれぞれatomicなclocked groupとしてmergeする。revisionはtotal-orderのHLC identity、parent revision、effective-from境界を持ち、参照中のancestor lineageを同期してfuture-only編集とconcurrent編集を収束させる。
- winning lineage外のrevisionが生成したtreeと、ancestor revisionがcutover境界以後に生成したtreeをsupersededとしてtransactionalにtombstone化してから、winning revisionでsettlementする。
- schedule設定変更・template snapshot置換の前に、同じclient operationで編集instant以下のdue occurrenceを旧revisionのまま100件ずつ全settleする。成功後だけcutoverし、新revisionの最初のoccurrenceをstrictly futureに置くため、旧payload historyは保持しない。
- `docs/02_機能仕様書.md`のF19 / F21と`docs/03_技術仕様書.md`のUUID例外、schema、task provenance、template / schedule、sync protocolをADR-021へ合わせて外科的に更新する。この仕様変更も2026-07-17のプロダクトオーナー承認に含む。

### やらないこと

- tagのsnapshot保存。tag導入後にsnapshot schema revisionを上げて追加する。
- status、due、scheduled_at、reminder、timer、assignee、task ID、rankのsnapshot保存。
- serverでの予定生成、平文予定の保持、90日等のcatch-up上限。
- 複数RRULE、RDATE、EXDATE、EXRULE、SECONDLY、MINUTELY、HOURLY。
- 互換fallback、dual read / dual write。既存taskのrecurrence provenanceはNULLにする。
- ranking、badge、祝賀演出。
- Android CI担当のcheckout、branch、worktreeへの変更。
- push、Pull Request作成、merge。

## 5. 実装手順

1. ADR-021、本work item、F19 / F21、技術仕様をレビューし、template snapshot、revision lineage、RRULE、cursor lattice、UUIDv5、streakの契約を確定する。
2. domain型、RRULE parser / normalizer / iterator、snapshot validation、deterministic ID、streak計算をtest-firstで追加する。
3. local schema v20 migration、storage repository、atomic settlement、task provenanceを追加し、v19 migrationと長期offlineを検証する。
4. sync protocol v6、field map / merge、Tenant Root DEK envelope、server migrationを追加し、2-client収束とfull resyncを検証する。
5. `TodoriClient` API、FRB typed DTO、起動・resume・post-pull settlementとsingle-flight再同期を追加する。
6. Flutterのroute、Templates画面、task詳細操作、英日ARB、validation、semanticsを追加する。
7. 全品質ゲート、Postgres統合、iOS / Android Rust cross-build、Visual QAを統合HEADで実行する。
8. 実装担当以外が統合HEADを独立検証し、指摘を修正・再検証してから完了記録とlocal commitを作る。

## 6. 受け入れ基準

- [x] snapshot subtreeがfield制限、100 node、48 KiB、安定node keyを守ってroundtripする。
- [x] RRULEのdaily / weekly / monthly / yearly、INTERVAL、COUNT、UNTIL、DST、存在しない月末日、端末timezone変更と無効入力をtestする。
- [x] 手動起票は保存済み既定listへ生成し、削除・archive済みならcanonical Inboxへfallbackする。
- [x] 自動起票はrootだけにoccurrenceの`scheduled_at`を設定し、dueなし・全node todoで生成する。
- [x] 100件分割、長期offline、終了規則、停止期間skip、future-only編集をtestする。
- [x] 2端末同時生成、再実行、cursor後退、offline復帰、full resyncで重複しない。
- [x] A端末でfuture-only編集後、未同期B端末が旧scheduleまたは旧template revisionで境界後を生成しても、同期後のlive treeがwinning lineageの1件だけになる。
- [x] 長期offlineでcursorが過去でも編集前settlementが旧revisionで全due occurrenceを生成し、編集失敗時にconfig / snapshotが変わらず、新revisionが編集instant以前へ遡及しない。
- [x] 異なるschedule設定のconcurrent編集、終了済み`Exhausted`対stale cursor、停止・再開競合が全端末で同じ設定・cursorへ収束する。
- [x] 日次・週次・月次、期限前後の完了、未完了、wont-do、reopen、進行中最新回、schedule revision変更のstreakをtestする。
- [x] COUNT / UNTIL最終回についてvirtual next occurrenceの前後、未完了をtestする。
- [x] v19からv20で既存task、sync metadata、tombstoneを保持し、provenanceをNULLにする。
- [x] templates / schedulesのTenant Root DEK roundtrip、wrong key、collection mismatch、tombstone、pull / apply、2-client収束をtestする。
- [x] Templates導線、保存、起票、preset / 詳細RRULE、停止・削除確認、英日、390 px、text scale 2.0、semanticsをFlutter testとVisual QAで確認する。
- [x] `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`が成功する。
- [x] Flutter analyze / test、hardcoded string、client boundary、FRB再生成差分、Postgres統合、iOS / Android Rust cross-build、`git diff --check`を実行し、結果を記録する。
- [x] before / after PNGを保存して目視確認し、統合HEADを独立検証者が再検証する。
- [x] snapshotは49,152 UTF-8 bytes以下のtyped atomic fieldとし、escape-heavy文字列・100 node・上限付近で最終encrypted envelopeが64 KiB以下になることをtestする。

## 7. 制約・注意事項

- local生成を正本とし、template / scheduleはTenant Root DEKでE2EE同期する。serverは平文、list linkage、生成ロジックを知らない。
- template編集は将来の起票だけへ作用する。template削除は参照scheduleも同一操作でtombstone化するが、生成済みtaskを変更しない。
- schedule無効化中は生成しない。再開はrevisionを増やし、再開後最初のoccurrenceへcursorを進めて停止期間を補完しない。
- 同一revisionではcursorを後退させない。設定変更はrevisionを増やし、将来分だけ新規則を使う。
- revisionはHLC identityでtotal orderを持ち、config / snapshotをfield単位に混ぜない。cursor latticeは同一revision内だけで`Pending(instant) < Exhausted`とし、`next_run_at=NULL`のExhaustedを最大値として復活させない。
- winning revisionのancestorとeffective-from境界を、provenanceを持つtaskが残る間は保持する。lineage外または境界後の旧revision taskはgenerated instanceの編集有無にかかわらずsupersededとしてtombstone化し、同期後の重複を残さない。
- canonical Inbox以外の削除・archive済み既定listを復活させない。
- 外部依存の仕様は公式資料を参照し、`rrule`の検証上限を無効化しない。
- pre-releaseのため旧schema / protocol互換を追加せず、現行最終形式へ直接更新する。

## 8. 完了報告に含めるべき内容

- domain / DB / sync / client / FRB / Flutterの実装結果と主要な設計差分。
- migration、収束、streak、RRULE、crypto / sync、UI testの具体的な証拠。
- 全品質ゲート、Postgres統合、cross-build、Visual QAの結果と環境制約。
- Visual QA PNGのpathと確認した状態。
- 独立検証の判定、検証者、再実行command、指摘と修正。
- local commit hashと未解決事項。push / PRを行っていないこと。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-17
- 結果: content-only subtree template、RRULE schedule、UUIDv5による予定回task tree、100件単位のlocal settlement、future-only revision lineage、streak、schema v20 / protocol v6、Tenant Root DEK同期、FRB API、英日Templates UIを実装した。手動起票はUUIDv7を維持し、archive / 削除済み既定listはcanonical Inboxへfallbackする。
- DB / sync: `templates` / `schedules`とtask provenanceを追加し、v19からの既存task・cursor・tombstoneを保持した。full resyncは`timer_sessions → tasks → schedules → templates → lists`の依存順、collection別stable cursor、never-synced dependency保護で処理する。server migrationとPostgres protocol v6 integration 21件が成功した。
- テスト: Rust workspaceはclient 52、domain 57、storage 93成功 / performance 1件手動skip、sync 84、server unit 12、Postgres integration 21を含め全成功した。追加契約テストで105 occurrenceを100 + 5へ分割、再実行0件、COUNT exhaustion、Inbox fallback、全RRULE頻度 / 終了条件 / DST / stored timezone、Tenant Root DEK wrong-key / collection AAD、escape-heavy 100 node・48 KiB近傍envelope 64 KiB以内を確認した。
- Flutter: `flutter analyze`は0 issue、`flutter test`は257成功 / Visual QA harness 1件意図的skip。Templates test 4件で導線、起票、英日、semantics、週次複数曜日、月次1〜31日、詳細RRULE validation、停止・削除確認、390 px / text scale 2.0を確認した。hardcoded string / client boundary / boundary self-testも成功した。
- 生成 / build: FRB再生成前後で生成5ファイルのhashが一致した。native Rust release、iOS Simulator arm64、Android arm64-v8a cross-buildが成功した。iOS linkerには既存のdeployment target 15.0をtarget 14.0が上書きするwarningが1件あるが、成果物生成は成功した。
- Visual QA: `app/build/visual_qa/p2_m8/before_lists.png`、`after_templates_en.png`、`after_templates_ja.png`、`after_templates_text_scale_2.png`を保存して目視し、背景、navigation選択、英日、390 px、text scale 2.0でoverflow / clippingがないことを確認した。PNGは全てfully opaqueである。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、Flutter analyze / test、hardcoded string、client boundary 2種、Postgres integration、iOS / Android cross-build、`git diff --check`が成功した。
- Commit: `a5772e5`（契約 / ADR）、`b776dc9`（実装）、`d213192`（独立検証指摘の修正）。本完了報告は後続のlocal docs commitに含める。
- 未解決: 本work item内はなし。Android接続実機検証はP2-M5、一般releaseの課金gateは別work itemを正本とする。push / PRは行っていない。

### 独立検証

- 判定: 合格
- 検証者: `/root/p2_m8_verifier`（実装担当外エージェント）
- 初回指摘: full-resync sweepの新collection未対応、週次 / 月次presetの指定UI不足、critical契約の統合テスト不足を理由にFAILとした。
- 修正: 全collection sweep / never-synced保護 / stable cursorを実装し、週次7曜日複数選択と月次1〜31日選択を追加した。full resync、105回補完、Inbox fallback、Tenant Root DEK / AAD、48 KiB近傍snapshot、390 px / text scale 2.0の回帰テストを追加した。
- 再検証: `cargo fmt --all -- --check`、domain recurrence 12、storage 93成功 / 1件手動skip、sync 84、client 52、Flutter analyze、Templates widget 4、`git diff --check`を再実行してPASS。新規blocking findingなし。
