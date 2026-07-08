# task-73: 削除同期ADR-010ドラフトとList DEK整合

> ステータス: 完了
> 作成日: 2026-07-08
> 作業日: 2026-07-08

## 1. 背景とコンテキスト

P2-M4 task-72で同期エンジンは動作したが、削除同期は `deleted=true` の暫定橋渡しに留まり、正式なtombstone/GC/削除競合の意味論はP2-M5へ残った。また、task-72完了報告では、`docs/03_技術仕様書.md` §4.8がlists本体を当該List DEKで暗号化すると定めている一方、実装はTenant Root DEKでlistsを暗号化している暫定状態が未解決事項として記録された。

本タスクではADR-010ドラフトを作成し、削除同期の正式設計を人間承認待ちとして記録する。実装は保守的に、削除tombstoneのblob空化、tombstone GC関数、List DEK整合に絞る。`410 Gone` とフル再同期はPhase 2後半へ送る。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/03_技術仕様書.md` §4.8、§6.2〜§6.6
- `docs/05_設計判断記録.md` ADR-005、ADR-009
- `docs/tasks/task-72-sync-engine.md` の `## 9. 完了報告`
- `core/sync/src/account.rs`
- `core/sync/src/envelope.rs`
- `core/sync/src/engine.rs`
- `app/rust/src/api.rs`
- `server/src/sync.rs`
- `server/src/routes/sync.rs`
- `server/tests/sync_server.rs`

## 3. ゴール

- `docs/05_設計判断記録.md` にADR-010ドラフトを追加し、ステータスを「Draft / 人間承認待ち」と明記する。
- ADR-010へ、削除tombstoneはrecord-id + deleted flag + HLC + seq等の最小メタデータのみ保持し、暗号blobは削除時に空化する設計を記録する。
- tombstone保持180日、GC、GC窓超過端末の410 Gone + フル再同期方針、削除/編集競合時のHLC比較、編集後勝ち時の復活を「サーバーからの再作成」として扱う方針を記録する。
- task-73時点の実装範囲を、削除tombstone blob空化とGC関数、List DEK整合に限定する。
- lists本体の同期暗号化をTenant Root DEKから当該List DEKへ修正し、登録時・リスト作成時に `wrap(DEK_list, MK)` をサーバーへ保存/配布できるようにする。
- 2クライアント統合テストを更新し、削除blob空化、GC、List DEKを使った同期が確認できること。

## 4. スコープ

### 想定変更ファイル

- `docs/05_設計判断記録.md`
- `docs/tasks/task-73-adr010-and-dek-alignment.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `core/sync/src/account.rs`
- `app/rust/src/api.rs`
- `server/src/sync.rs`
- `server/src/routes/sync.rs`
- `server/tests/sync_server.rs`

### やること

1. `git status --short` で作業前状態を確認する。
2. ADR-010をDraft/人間承認待ちとして追加する。
3. サーバー側で `deleted=true` pushの保存blobを空byte列へ正規化する。
4. サーバー側に180日cutoffを受け取るtombstone GC関数を追加する。
5. 登録時のkey bundleが実リストIDごとのList DEKを含むようにし、ログイン時に同じList DEKを復元できることを維持する。
6. ログイン後に新規リストを作る場合、List DEKを生成し、`wrap(DEK_list, MK)` をサーバーへupsertしてからlist本体のoutboxを積む。
7. lists本体の暗号化/復号を当該List DEKへ切り替える。
8. tasksの復号は所属List DEKを使う。新規端末でローカルtask行がない場合は、手元のList DEKを試行して復号し、復号後の `list_id` で鍵対応を確定する。
9. Tenant Root DEK fallbackは削除し、List DEKが無いrecordは復号失敗/同期失敗として扱う。
10. 既存テストデータへの互換レイヤは作らない。未リリースであるため、テストは新しいkey bundle前提へ更新する。
11. README/BACKLOGをtask-73完了状態へ更新し、ADR-010を要人間判断へ承認待ちとして登録する。

### やらないこと

- `410 Gone` とフル再同期の実装。
- device最終pull時刻からのGC窓超過検知。
- 削除/編集競合のUI通知、監査UI、手動マージUI。
- Org共有のsealed box実装、除名時のList DEKローテーション実装。
- git commit。

## 5. 実装手順

1. task-72完了報告の未解決事項を確認し、List DEK暫定箇所をgrepする。
2. ADR-010を追加し、削除blob空化、180日GC、410/フル再同期、削除競合、代替案を記録する。
3. `core/sync/src/account.rs` の登録key bundle生成を、実リストID一覧を受け取ってList DEKを作る形へ変更する。
4. サーバーへList DEK bundle upsert APIを追加し、既存の認証/tenant認可を通す。
5. `app/rust/src/api.rs` のlist/task暗号化DEK解決をList DEK厳格運用へ変更する。
6. `server/src/sync.rs` で削除pushのblob空化とGC関数を追加する。
7. `server/tests/sync_server.rs` のaccount/sync統合テストを更新し、List DEK、list key upsert、削除blob空化、GCを確認する。
8. `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace`、Flutter品質ゲート、`git diff --check` を実行する。
9. 本指示書へ `## 9. 完了報告` を追記する。

## 6. 受け入れ基準

- [x] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。
- [x] ADR-010が `docs/05_設計判断記録.md` にDraft/人間承認待ちとして追加されている。
- [x] ADR-010に削除blob空化、tombstone 180日保持、GC、410 Gone + フル再同期、削除/編集競合のHLC比較、編集後勝ち時の再作成扱い、代替案が記載されている。
- [x] `deleted=true` pushは、クライアントが非空blobを送ってもサーバー保存時に空blobへ正規化される。
- [x] tombstone GC関数が追加され、cutoff以前の `deleted=true` 行を削除するテストがある。
- [x] lists本体の暗号化/復号が当該List DEKを使い、Tenant Root DEK fallbackが残っていない。
- [x] 登録時と新規リスト作成時に `wrap(DEK_list, MK)` がサーバーへ保存される。
- [x] 2クライアント統合テストがList DEK前提で通り、削除伝播、outbox永続性、復号失敗スキップも維持されている。
- [x] `docs/tasks/BACKLOG.md` の要人間判断にADR-010承認待ちが登録されている。

## 7. 制約・注意事項

- ADR-010はDraftであり、人間承認まで採用済みにしない。
- `docs/03_技術仕様書.md` §4.8を正とし、lists本体はTenant Root DEKではなく当該List DEKで暗号化する。
- List DEKが見つからない場合にTenant Root DEKへfallbackしない。誤った鍵で暗号化したblobを増やすより、同期失敗/復号失敗として観測可能にする。
- 削除tombstoneは同期のためのメタデータであり、削除済みコンテンツの暗号blobを保持しない。
- `410 Gone` とフル再同期は設計だけ記録し、本タスクで実装しない。
- 秘密情報（password、session token、MK、Tenant Root DEK、List DEK、Device Key、exportKey、Recovery Key、復号済みplaintext）をログやDart境界へ出さない。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- ADR-010ドラフトの設計要約
- 削除tombstone blob空化とGC関数の実装内容
- List DEK整合の実装内容（登録時、リスト作成時、lists/tasks暗号化/復号）
- 既存テストデータ互換への判断
- 追加/変更したテストと対象
- 品質ゲート実行結果
- 変更ファイル一覧
- 未解決事項

## 9. 完了報告

作業日: 2026-07-08

読んだファイル:

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-72-sync-engine.md` の `## 9. 完了報告`
- `docs/tasks/task-73-adr010-and-dek-alignment.md`
- `docs/03_技術仕様書.md` §4.8、§6.3、§6.4、§6.5、§6.6
- `docs/05_設計判断記録.md` ADR-005、ADR-009、ADR-010
- `core/sync/src/account.rs`
- `core/sync/src/envelope.rs`
- `core/sync/src/engine.rs`
- `app/rust/src/api.rs`
- `server/src/sync.rs`
- `server/src/routes/sync.rs`
- `server/src/auth.rs`
- `server/tests/sync_server.rs`

ADR-010ドラフトの設計要約:

- 状態は `Draft / 人間承認待ち` とした。
- 削除は `deleted=true` のtombstoneとして同期ストアに残す。
- tombstoneの `encrypted_blob` は空byte列へ正規化する。
- サーバー保持情報は `tenant_id`、`record_id`、`collection`、`seq`、`hlc`、`deleted=true`、`updated_at` の最小メタデータに限定する。
- tombstone保持期間は180日とし、GC窓超過端末は将来 `410 Gone` + フル再同期で復旧する。
- 削除/編集競合はレコードHLC比較とし、編集後勝ちによる復活はローカルUndoではなくサーバー由来の再作成として扱う。
- 代替案として、暗号blob保持、即時物理DELETE、無期限tombstone、削除常勝を却下した。

削除tombstone blob空化とGC関数:

- `server/src/sync.rs` の `validate_push_op()` で `deleted=true` のpushを `Vec::new()` へ正規化する。
- クライアントが削除pushで非空blobを送っても、`sync_records.encrypted_blob` には空byte列が保存される。
- `server/src/sync.rs` に `TOMBSTONE_RETENTION_DAYS = 180` と `gc_tombstones(pool, cutoff)` を追加した。
- `gc_tombstones()` は `deleted = true AND updated_at < cutoff` の `sync_records` 行を物理削除し、削除行数を返す。
- `410 Gone`、フル再同期、device最終pull時刻に基づくGC窓超過判定は実装していない。

List DEK整合:

- 登録時の `AccountClient::register()` は既存ローカルlist ID一覧を受け取り、各listごとに `generate_list_dek()` した `wrap(DEK_list, MK)` を登録key bundleへ含める。
- `app/rust/src/api.rs` の登録フローは `local_list_ids_for_registration()` で通常listとarchive済みlistのIDを集め、登録key bundleへ渡す。
- `server/src/auth.rs` は登録key bundle内の `list_deks` を `list_key_bundles` へ保存し、ログイン時に全List DEK bundleを返す既存経路を維持する。
- `server/src/routes/sync.rs` / `server/src/sync.rs` に `POST /v1/tenants/{tenant_id}/list-keys` を追加し、認証済みsessionで `list_key_bundles` をupsertできるようにした。
- ログイン後の新規list作成では、`ensure_list_dek_for_list()` がList DEKを生成し、`wrap(DEK_list, MK)` をサーバーへupsertしてからローカルruntime鍵へ追加し、list本体のoutboxを積む。
- lists本体の暗号化/復号は当該list IDのList DEKを使う。
- tasksの暗号化は所属list IDのList DEKを使う。
- tasksのpull復号では、既存ローカルtaskのlist IDに対応するList DEKを優先し、新規端末など既存taskがない場合は手元のList DEKを順に試行し、復号後の `list_id` から対応List DEKを確定する。
- Tenant Root DEK fallbackは削除した。List DEKがないlist/task recordは復号失敗または同期失敗として扱う。

既存テストデータ互換への判断:

- 未リリースの同期実装であるため、Tenant Root DEKで暗号化されたlists blobへの互換レイヤは追加していない。
- テストは新しいkey bundleとList DEK前提へ更新した。

追加/変更したテスト:

- `core/sync/src/account.rs`: 登録key bundleが指定list IDのList DEKを含み、ログインunwrapで同じList DEKを復元することを確認した。
- `server/tests/sync_server.rs`: `deleted=true` pushの非空blobが保存時に空byte列へ正規化されることを確認した。
- `server/tests/sync_server.rs`: cutoff以前のtombstoneを `gc_tombstones()` が削除することを確認した。
- `server/tests/sync_server.rs`: `AccountClient::upsert_list_key_bundle()` で追加List DEK bundleが保存されることを確認した。
- `server/tests/sync_server.rs`: 2ローカルDB統合テストをList DEK前提へ更新し、削除伝播、outbox永続性、復号失敗スキップを維持した。

秘密情報grep監査:

- 対象: `git diff --name-only` の変更ファイル、および `app/rust/src`、`core/sync/src`、`server/src`、`server/tests`。
- 検索語: `dbg!`、`println!`、`eprintln!`、`debugPrint`、`tracing::`、`password`、`session_token`、`master_key`、`tenant_root_dek`、`list_dek`、`device_key`、`export_key`、`recovery_key`、`SyncPlaintext`、`plaintext`。
- 本タスク実装で、password、session token、MK、Tenant Root DEK、List DEK、Device Key、exportKey、Recovery Key、復号済みSyncPlaintext/record plaintextをログ、Debug出力、Flutter error表示へ出す箇所は見つからなかった。
- 既存/テスト内の識別子名・固定テスト値・固定エラー文言は該当したが、実秘密値の出力はなかった。

品質ゲート実行結果:

- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: 成功
  - `server/tests/sync_server.rs`: 5 passed
  - `todori_storage`: 48 passed, 1 ignored
  - `todori_sync`: 29 passed
  - `todori_app_bridge`: 4 passed, 1 ignored
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter analyze`: 成功
- `cd app && flutter test`: 成功（123 passed、visual QA harness 1 skipped）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `git diff --check`: 成功

変更ファイル一覧:

- `app/rust/src/api.rs`
- `core/sync/src/account.rs`
- `docs/05_設計判断記録.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/README.md`
- `docs/tasks/task-73-adr010-and-dek-alignment.md`
- `server/src/routes/sync.rs`
- `server/src/sync.rs`
- `server/tests/sync_server.rs`

未解決事項:

- ADR-010はDraftであり、人間承認待ち。
- `410 Gone`、フル再同期、device最終pull時刻に基づくGC窓超過判定は未実装。
- 削除/編集競合のUI通知、監査UI、手動マージUIは未実装。
- Org共有のsealed List DEK配布、除名時のList DEKローテーションは未実装。
- マルチプラットフォーム検証はP2-M5後半へ継続。
