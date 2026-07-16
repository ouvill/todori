---
id: 019f6a1c-d4a5-7ad1-bd39-6eb9662d5537
title: CI cache optimization and sccache benchmark
status: active
lane: standard
milestone: maintenance
---

# CI cache optimization and sccache benchmark

## 1. 背景とコンテキスト

GitHub Actionsの直近成功runでは、docs-only PRでもRust、Flutter、Worker、fuzzの全jobが実行され、完了まで約6分、runner使用時間の合計で約11分を要した。大容量cacheはhitしているが、Linux Cargo cache約2.47 GBの復元に約48秒、Flutter SDK約2.07 GBに約80秒を要する。またPR refへ保存されたCargo target cacheはmainや兄弟PRから再利用できず、repository cacheは2026-07-16時点で約10.63 GiBに達している。

安全性を落とさず、明らかなdocs-only変更だけ重いjobを省略する。大容量cacheはPRでrestore-onlyとし、mainでのみ更新する。Rustのtarget cache縮小やsccache採用は推測で決めず、同一コマンドのA/B計測で判断する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `.github/workflows/ci.yml`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `Cargo.toml`
- `app/rust/Cargo.toml`

## 3. ゴール

- docs-only変更ではsecret scanを維持しつつ、Rust、Flutter、Worker、fuzzの重いjobを安全に省略する。
- Linux/macOS Cargo target cacheとfuzz target cacheをPRではrestore-onlyにし、PR固有の大容量cache生成を止める。
- 現行target cacheとsccacheを同じRust品質ゲートで比較し、cold/warmの実測値から採否を判断する。

## 4. スコープ

### やること

- 未知の変更をfull CIへ倒すfail-openなdocs-only判定を追加する。
- docs-only判定スクリプトの回帰テストを追加する。
- required checkをPendingにしないようworkflow自体は常に起動し、job単位でskipする。
- 大容量cacheをrestore/save分離し、PRでsaveしない。
- SHA固定したMozilla sccache actionを使うA/B benchmark jobを、明示的なPR labelでのみ起動できるようにする。
- A/Bでは同一runner image、toolchain、`cargo clippy`、`cargo test`を用い、経過時間、cache hit、sccache statsを記録する。

### やらないこと

- docs以外の変更に対する細粒度なjob選別。
- 計測前のtarget cache廃止、`CARGO_INCREMENTAL=0`導入、sccacheの通常CI採用。
- Flutter testのLinux移行やテスト分割。
- branch protectionの変更。

## 5. 実装手順

1. eventと比較対象SHAから変更ファイルを取得し、すべてが保守的なdocs allowlistに入る場合だけ`docs_only=true`を返すスクリプトを作る。
2. schedule、取得失敗、空diff、未知pathをすべてfull CIへ倒すテストを作る。
3. change classification jobの出力でRust、Flutter、Worker、fuzz jobをskipし、security jobは常時実行する。
4. Rust、Flutter、fuzzのcacheをrestore/saveへ分離し、saveをnon-PR成功時だけに限定する。
5. label付きPRでのみtarget cache方式とsccache方式を並列実行するbenchmark jobを追加する。
6. workflow構文、shell test、既存境界検査を実行する。
7. GitHub上でbenchmarkをcold/warm各1回以上実行し、通常CIへのsccache採否を決める。

## 6. 受け入れ基準

- [ ] `docs/**`のみの変更をdocs-onlyと判定する。
- [ ] code、workflow、Cargo、未知pathとの混在はfull CIと判定する。
- [ ] scheduleと判定不能時はfull CIと判定する。
- [ ] docs-only時も`Dependency and secret gates`が実行される。
- [ ] docs-only時のRust、Flutter、Worker、fuzz jobはjob単位でskipされる。
- [ ] PRでは大容量cacheのsave stepが実行されない。
- [ ] main pushまたはscheduleではcache miss時に大容量cacheをsaveできる。
- [ ] A/Bの両方式が同じRust品質ゲートを実行し、比較可能な時間とcache統計を残す。
- [ ] sccacheは実測で優位性が確認できるまで通常CIへ採用しない。
- [ ] `sh tool/ci/test_classify_changes.sh`
- [ ] `sh app/tool/check_client_boundaries.sh`
- [ ] `sh app/tool/test_client_boundaries.sh`
- [ ] `git diff --check`

## 7. 制約・注意事項

- path判定は最適化であり、正しさより実行時間を優先してはならない。allowlist外は必ずfull CIへ倒す。
- workflow-levelの`paths-ignore`はrequired checkをPendingにし得るため使わない。
- cacheにsecret、token、credentialを含めない。
- third-party actionはcommit SHAへ固定する。
- PR cacheのbranch scopeとGitHubのcache evictionを前提にする。
- A/Bのcold runだけで結論を出さず、同じPR refでwarm runも計測する。

## 8. 完了報告に含めるべき内容

- docs-only/mixed/unknown/scheduleの判定テスト結果。
- PRとmainでのcache save条件。
- A/Bのrun URL、job時間、cacheサイズまたはhit状況、sccache hit率・error数。
- sccacheの採用・不採用判断と根拠。
- 実行した品質ゲート、skip、環境制約、未解決事項。
