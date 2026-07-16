---
id: 019f6a1c-d4a5-7ad1-bd39-6eb9662d5537
title: CI cache optimization and sccache benchmark
status: done
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

- [x] `docs/**`のみの変更をdocs-onlyと判定する。
- [x] code、workflow、Cargo、未知pathとの混在はfull CIと判定する。
- [x] scheduleと判定不能時はfull CIと判定する。
- [x] docs-only時も`Dependency and secret gates`が実行される。
- [x] docs-only時のRust、Flutter、Worker、fuzz jobはjob単位でskipされる。
- [x] PRでは大容量cacheのsave stepが実行されない。
- [x] main pushまたはscheduleではcache miss時に大容量cacheをsaveできる。
- [x] A/Bの両方式が同じRust品質ゲートを実行し、比較可能な時間とcache統計を残す。
- [x] sccacheは実測で優位性が確認できるまで通常CIへ採用しない。
- [x] `sh tool/ci/test_classify_changes.sh`
- [x] `sh app/tool/check_client_boundaries.sh`
- [x] `sh app/tool/test_client_boundaries.sh`
- [x] `git diff --check`

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

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-16
- 結果: docs-only変更だけ重い4 jobをskipするfail-open判定と、PRの大容量Cargo cacheをrestore-onlyにする構成を導入した。sccacheはcold/warm A/Bで現行target archiveより遅かったため採用せず、一時benchmarkを最終workflowから除去した。
- 証拠: classifier回帰13件、actionlint、既存品質ゲート、GitHub Actions cold/warm各1回がPASSした。実測値とrun URLは下記に記録する。
- Commit: `ed35d0d`（実装とA/B workflow）、`aab3248`（A/B結果反映と一時benchmark除去）
- 未解決: GitHub UI上のdocs-only job skipとtrusted non-PR cache saveは、workflowがmainへ入った後の該当runで実地確認する。

- `tool/ci/classify_changes.sh`を追加し、PRはbase/headのthree-dot diff、pushはbefore/headのtwo-dot diffから変更pathを取得する。`docs/**`、root Markdown、`LICENSE*`だけをdocs-onlyとし、schedule、未知event、zero before、空diff、取得失敗、allowlist外pathはすべてfull CIへ倒す。
- change classification jobを常時起動し、docs-only時だけWorker、Rust、Flutter、fuzzをjob単位でskipする。`Dependency and secret gates`は判定に依存せず常時実行する。classifier job自体が失敗した場合も`always() && !cancelled()`で重いjobを実行する。
- Linux Rust、macOS Flutter Rust、fuzzの大容量Cargo cacheを`actions/cache/restore`と`actions/cache/save`へ分離した。PRはrestore-only、main pushとscheduleは成功かつexact miss時だけ同じprimary keyへsaveする。
- 一時的なlabel-gated sccache jobで同一のRust 1.97.0、fmt、client boundary、clippy、workspace testを現行target archive方式と並列実行した。cold/warm計測後、優位性がなかったため一時jobとlabel triggerを最終workflowから削除した。

#### A/B結果

- [cold run / attempt 1](https://github.com/ouvill/todori/actions/runs/29486163712): 現行Rust target cache 3分12秒、sccache 11分47秒。sccacheは全体hit 9.74%、Rust hit 0%、miss 3,502、cache write error 1,518だった。現行jobの約2.47 GB target archive復元は76秒だった。
- [warm run / attempt 2](https://github.com/ouvill/todori/actions/runs/29486163712/attempts/2): 現行Rust target cache 2分27秒、sccache 6分10秒。sccacheは全体hit 64.95%、Rust hit 87.92%まで上がったが、C/C++ miss 1,240、cache write error 528が残り、現行jobより3分43秒遅かった。
- sccacheはcoldで約3.7倍、warmでも約2.5倍遅く、GitHub Actions Cache backendへの細粒度I/OとC/C++ buildのmissがこのworkspaceでは不利だった。通常CIには採用せず、現行target archiveを維持する。
- 同じwarm runのFlutter jobは4分39秒だった。cold runの6分06秒の内訳はCargo restore 29秒、Flutter SDK restore 81秒、FRB regenerate 53秒、Rust release library build 36秒、Flutter analyze 24秒、Flutter test 117秒であり、Flutter testだけでなくSDK復元、bindgen/FRB、Rust buildも主要因である。

#### 検証

- official actionlint v1.7.12で`.github/workflows/ci.yml`: PASS。Ruby YAML parse、`sh -n`、`git diff --check`: PASS。
- `sh tool/ci/test_classify_changes.sh`: PASS。docs-only PR/push、日本語docs path、root Markdown、削除をtrue、code、mixed、workflow、codeからdocsへのrename、schedule、未知event、zero before、空diff、invalid SHAをfalseとして確認した。
- 実履歴のdocs-only PR base/headをtrue、Flutter変更PR base/headをfalseと判定した。
- `cargo fmt --all -- --check`、client boundary check/test、secret pattern check、crypto dependency pin check: PASS。
- GitHub cold/warm runでは全jobがPASSし、PR上のRust、Flutter、fuzzのsave stepがskipされた。

#### 未解決事項

- docs-only時のjob skipはclassifierのfixture、実履歴、workflow条件で検証した。変更workflowがmainへ入る前にdocs-only PRだけを作ることはできないため、GitHub UI上の実skipはmerge後の最初のdocs-only PRで確認する。
- main pushまたはscheduleのexact cache miss時にsaveされることはworkflow条件で確認した。PR #22は意図どおりrestore-onlyであり、trusted non-PRの実saveはmerge後のrunで確認する。

### 独立検証

- 判定: 合格
- 根拠: GitHub APIとjob logからcold/warmの全job成功、job時間、sccache hit/miss/error、Flutter step内訳、PR save stepのskipを照合した。最終workflowで一時benchmarkとlabel triggerの除去、fail-open、security常時実行、PR restore-only/non-PR save条件を再確認し、actionlint v1.7.12、classifier回帰、`git diff --check`を再実行してPASSした。重大・中程度のコード指摘はなかった。
- 検証者: 実装を担当していない独立検証エージェント
