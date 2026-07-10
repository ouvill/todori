# task-95: Fuzzy-scan full resync / GC horizon

> ステータス: 進行中（server/protocol・storage/client実装）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

ADR-010はtombstoneを180日後にGCし、テナントごとの`gc_horizon_seq`より古い非zero cursorをfull resyncへ送る方針を定めた。ADR-012はfull resyncを厳密な過去snapshotではなく、更新で移動しないstable keyによるcurrent-state fuzzy scanと`base_seq`後のdelta catch-upとして定義した。

task-92〜94により、Flutter / CLI / MCPの共通入口は`todori-client`の`TodoriClient`へ集約され、Flutter bridgeからrepository・鍵・同期coordinatorが除去された。本taskではこの境界を維持したまま、GC後の端末と新規端末が、別端末の更新を止めず、欠落・未ACK local変更の消失・crash後の不整合なしにfull resyncできるproduction経路を実装する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/STATUS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §6（同期、full resync、GC horizon）
- `docs/05_設計判断記録.md` ADR-010 / ADR-012
- `docs/dev/client-profile-architecture.md`
- `docs/tasks/task-92-client-profile-full-migration.md`
- `docs/tasks/task-94-rust-client-naming-cleanup.md`
- `core/sync/`、`core/storage/`、`core/client/`、`server/`の現行protocol・schema・同期実装と統合test

## 3. ゴール

- tombstone GC後と新規profileの双方で、安全かつ有限にfull resyncをclosureできる。
- base scan中も別端末の更新を止めず、scan中の作成・更新をdeltaで回収する。
- 未ACK outboxを持つlocal recordをsweepせず、serverに存在しない安全なlocal recordだけを除去する。
- base、delta、mark、sweep、cursor確定の各crash windowから同じresyncを安全に再試行できる。
- 既存local dataを新規tenantへ登録する経路でseed-before-sweepを守る。
- `TodoriClient::sync_now`を唯一の高水準同期入口として維持し、Flutter / FRB公開call surfaceを変えない。
- strict snapshotやbase scan全体を覆う長時間DB lockに依存しない。

## 4. スコープ

### やること

- `todori-sync`: continuity / resync protocol型、stable-key cursor、base/delta page、high-water closure条件、state machineとstorage/server traitを実装する。
- `todori-storage`: resync generation、record mark、進捗、cursor、outbox保護付きsweepを支えるbreaking local schemaと短いtransaction primitiveを実装する。
- `todori-client`: SQLite adapter、preflight、seed、base scan、delta catch-up、mark/sweep、cursor確定、crash recoveryの実行順序を`TodoriClient::sync_now`配下へ統合する。
- `todori-server`: server transaction内の`base_seq`取得、stable-key current-state page、GC horizon永続化とpreflight判定、delta rowsと同一transactionの`high_water`、closureに必要なAPIを実装する。
- protocol/server/local schemaは互換shimなしで正しい最終形へbreaking変更する。
- production 2-client経路と各crash windowを含む自動testを追加する。

### やらないこと

- aggregate削除scope / epoch、Canonical Inbox、server RLS hardening。
- Flutter/Dart公開API、FRB関数signature、画面、生成物の変更。
- `todori_app_bridge`へのrepository、鍵、resync coordinator、下位crate直接依存の追加。
- strict historical snapshot、scan全体を覆う長時間Postgres / SQLite transactionやDB lock。
- 互換shim、dual read/write、旧形式fallback、bare `core` crate。
- private repoの変更。

## 5. 実装手順

1. 現行protocol、server schema/query、local schema、`TodoriClient::sync_now`の実行順序とテストfixtureを調査し、共有interfaceとmigrationの依存順を確定する。
2. `todori-sync`へpreflight判定、base/delta page型、stable-key cursor、`has_more=false`かつcursorがpage `high_water`へ到達した場合だけ成立するclosure条件を追加する。
3. `todori-server`へtenant sequence / GC horizon schema、server transaction内`base_seq`取得、`seq`で移動しないstable-key scan、`seq > base_seq` delta、同一transaction high-waterを実装する。base rowsは`seq <= base_seq`へ限定しない。
4. `todori-storage`へresync generation・進捗・mark・outbox保護付きsweep・closure cursor確定を短いtransactionで再試行できるschema/APIとして実装する。
5. `todori-client`でoutbox読取より先にpreflightし、`0 < since < gc_horizon_seq`と`since=0`を区別する。必要時はgenerationを再開/作成し、base、delta、closure、sweep、cursor確定、通常pushを順序づける。
6. 新規tenant binding時は既存local recordをtransactional seed/outboxへ登録してからresync/sweepし、未ACK outboxで保護されたrecordをclosure後の通常pushへ渡す。
7. 必須test、production 2-client収束test、FRB公開surface/boundary checkを実行し、全品質ゲートを統合HEADで通す。
8. 実装を担当していないエージェントが独立検証し、P1 / P2 / P3があれば修正と再検証を繰り返す。

## 6. 受け入れ基準

- [ ] 空serverからのfull resyncがclosureし、最終cursorをclosure時high-waterへ設定する。
- [ ] `since=0`はGC horizonが存在しても拒否されずfull resyncへ進み、非zero cursorだけが`0 < since < gc_horizon_seq`でcontinuity lossとなる。
- [ ] `0 < since < gc_horizon_seq`ではlocal key bundle/entity outbox pushより前にfull resyncへ遷移する。
- [ ] 最大active record seqがhorizon未満でもserver preflight / full resyncが正しく動作する。
- [ ] base開始時にserver transaction内で`base_seq`を取得し、current stateを更新で移動しないstable keyでpage走査し、baseを`seq <= base_seq`へ限定しない。
- [ ] page境界付近の同時作成・更新を欠落せず、base scan中に取り逃した変更を`seq > base_seq`のdeltaで回収する。
- [ ] delta page rowsと同じserver transactionで`high_water`を取得し、`has_more=false`だけ、またはhigh-water未到達ではclosure扱いしない。
- [ ] clientがresync generationを作成/再開し、base/deltaで確認したrecordをmarkする。
- [ ] closure後、未ACK outboxを持つlocal recordはsweepせず、serverに存在せずmarkされなかった安全なlocal recordだけをsweepする。
- [ ] base scan、delta、mark、sweep、cursor確定の各crash windowから再試行して同じ最終状態へ収束する。
- [ ] 既存local dataの新規tenant登録でseed-before-sweepを守り、未push dataを失わない。
- [ ] 2-client production経路がfull resync中の同時更新を含め最終的に収束する。
- [ ] `TodoriClient::sync_now`が高水準入口のままで、Flutter/FRB公開call surfaceとbridge boundaryが不変である。
- [ ] strict snapshot、長時間DB lock、互換shim、dual形式、旧fallbackを追加していない。
- [ ] `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`が成功する。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`、`cd app && flutter analyze`、`cd app && flutter test`が成功する。
- [ ] hardcoded strings、client boundaries、boundary negative test、`git diff --check`が成功する。
- [ ] 独立検証でP1 / P2 / P3指摘がない。

## 7. 制約・注意事項

- 暗号blob、鍵、復号済みplaintext、session tokenをログ、test失敗表示、完了報告へ出さない。
- protocol、storage/client transaction、server transactionの責務を混在させず、Flutter bridgeへ同期実装を漏らさない。
- recordのcollectionは不変とし、stable keyは更新で移動しない値だけで構成する。
- `base_seq`はbase snapshot上限ではなくdelta開始境界である。base queryへ`seq <= base_seq`条件を加えない。
- closure前にabsence sweepを開始しない。closure cursorとpage `high_water`の一致を必須とする。
- sweepは未ACK `sync_outbox`をrecord単位で保護し、seed-before-sweepと同じ安全条件を使う。
- network I/OをSQLite transaction内へ置かず、server側もpage単位の短いtransactionとする。
- FRB生成物は手編集しない。公開signatureを変えないためcodegen差分を発生させない。
- Docker / Flutter SDKがsandbox制約で失敗した場合は、コード失敗と区別し、承認付き実行へ切り替えて再検証する。

## 8. 完了報告に含めるべき内容

- server/local schema versionと、追加・変更したtable / constraint / index / migration。
- protocol型、endpoint / trait、stable-key cursor、base/delta/high-water closureの具体的な契約。
- `TodoriClient::sync_now`のpreflight、seed、resync、sweep、push順序とcrash recovery境界。
- 必須test名、2-client production test、全品質ゲートの実測結果。
- Flutter/FRB公開call surface不変とclient boundary維持の根拠。
- 独立検証の判定とP1 / P2 / P3、commit hash、未解決事項。
