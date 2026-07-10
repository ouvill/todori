# task-96: 同期server RLS hardening

> ステータス: 完了（non-owner runtime role・RLS強制・cross-tenant検証、独立再検証合格）
> 作業日: 2026-07-11

## 1. 背景とコンテキスト

`sync_records`と`sync_records_history`はRLSを有効化しているが、実際のpolicy、non-owner application role、tenant context設定、`FORCE ROW LEVEL SECURITY`がない。現状はAPI認可と各SQLの`tenant_id`条件だけに依存しており、ADR-012が要求する多層テナント分離を満たしていない。

本taskは、SQLのtenant条件を誤って省略してもPostgresが別tenantの行を返さず、書込先tenantの偽装も拒否するDB境界を実装する。2026-07-11にプロダクトオーナーから本セキュリティ変更への着手承認を得た。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/STATUS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md` §6.1
- `docs/05_設計判断記録.md` ADR-003 / ADR-012
- `docs/tasks/task-86-protocol-v2-cas.md`
- `docs/tasks/task-95-fuzzy-scan-full-resync-gc-horizon.md`
- `server/migrations/`
- `server/src/db.rs`、`server/src/auth.rs`、`server/src/sync.rs`
- `server/tests/auth_server.rs`、`server/tests/sync_v2.rs`
- `tool/dev_server.sh`、`docs/ops/runbook-db-migration.md`

## 3. ゴール

- serverの通常queryをtable owner / superuser / BYPASSRLSではないruntime loginで実行し、NOLOGIN group role`todori_app`の権限を`INHERIT`する。
- tenant/user contextをtransaction-localに設定し、Neonのtransaction poolと両立させる。
- tenant所有データをRLS policyと`FORCE ROW LEVEL SECURITY`で分離する。
- SQLからtenant条件を省略しても別tenantの読取・更新・削除ができず、別tenantへのinsertも拒否されることを実Postgresで検証する。
- OPAQUE登録・ログイン、鍵bundle、push/pull、full resync、GC horizonの既存経路を維持する。

## 4. スコープ

### やること

- `todori_app` NOLOGIN / NOBYPASSRLS role、table権限、RLS policy、`FORCE ROW LEVEL SECURITY`を追加する前方migration。
- `tenants`、`tenant_members`、`tenant_seq`、`tenant_key_bundles`、`list_key_bundles`、`sync_records`、`sync_records_history`をtenant/user contextで保護する。
- migration接続とapplication poolを分離し、application pool接続時にruntime loginのrole属性・非owner・`todori_app`権限継承を検証する。
- 認証済みuser / tenant contextを`set_config(..., true)`で短いtransactionへ設定する共通helper。
- contextなし、tenant A context、tenant B context、誤tenant writeを検証するcross-tenant integration test。
- ローカル起動とDB migration runbookへruntime role要件を記録する。

### やらないこと

- OPAQUE、同期wire protocol、暗号payload、local SQLite schema、Flutter / FRB公開APIの変更。
- AWS / Neon本番環境へのrole作成・migration適用・デプロイ。
- 課金・Organization共有・複数tenant選択UIの実装。
- RLSを認可の代替として扱うこと。既存API認可と明示的な`tenant_id`条件は維持する。
- private repoの変更。

## 5. 実装手順

1. RLS migrationを追加し、`todori_app`の属性・権限、各tableのpolicyと`FORCE ROW LEVEL SECURITY`を冪等に定義する。
2. `db` moduleにapplication poolとtransaction-local user / tenant context helperを追加する。
3. OPAQUE登録・ログイン・session認証と全tenant queryをcontext付きtransactionへ移す。
4. test fixtureをmigration/admin poolとapplication poolへ分け、既存API testを実際の`todori_app` roleで通す。
5. RLS catalog、実効role、contextなしfail-closed、WHERE省略時のtenant分離、誤tenant write拒否を専用integration testで検証する。
6. ローカル起動scriptとrunbookを新しい接続境界へ合わせる。
7. 統合HEADで品質ゲートを実行し、実装結果を完了報告へ記録する。
8. 実装を担当していないエージェント、別セッション、または人間が独立検証し、合格後にtaskとSTATUSを完了へ更新する。

## 6. 受け入れ基準

- [x] `todori_app`がNOLOGIN / NOSUPERUSER / NOBYPASSRLSで、application poolのruntime loginがLOGIN / non-owner / NOSUPERUSER / INHERIT / NOBYPASSRLSかつ`todori_app`権限を利用できる。
- [x] 対象7tableでRLS policyと`FORCE ROW LEVEL SECURITY`が有効である。
- [x] tenant/user contextはtransaction-localであり、commit / rollback後にpool接続へ残留しない。
- [x] contextなしのapplication queryがtenant所有行を取得できない。
- [x] `WHERE tenant_id = ...`を省略した読取でも現在tenantの行だけが返り、別tenantの暗号blob・鍵bundle・membership・sequenceへ到達しない。
- [x] 現在tenant contextから別tenantの更新・削除は0件となり、別tenant IDでのinsertはRLS violationになる。
- [x] OPAQUE登録・ログイン、鍵bundle、push/pull、full resync、tombstone GCの既存統合testが成功する。
- [x] runtime loginとmigration ownerの分離、`todori_app` membership、秘密情報を残さない接続設定がrunbookに記録されている。
- [x] `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`が成功する。
- [x] `sh app/tool/check_client_boundaries.sh`、`sh app/tool/test_client_boundaries.sh`、`git diff --check`が成功する。
- [x] Flutter / FRB公開surfaceを変更していない。
- [x] 独立検証が合格している。

## 7. 制約・注意事項

- RLSは既存のAPI認可と明示的なtenant条件へ追加する多層防御であり、どちらも削除しない。
- tenant/user contextは認証済み値だけから設定し、HTTP requestの任意値だけでアクセスを許可しない。
- contextは必ずtransaction-localとし、session-level `SET`でconnection poolへ残留させない。
- 通常server poolでowner / superuser / `BYPASSRLS` roleを使わない。本番はmigration用direct owner URLとruntime用pooled non-owner URLを分離し、transaction poolで保持されないsession-level `SET ROLE`へ依存しない。
- 定期GCのような全tenant保守処理はapplication poolへ混在させず、migration/maintenance権限の明示的な経路でだけ行う。
- session token、DB URL、role password、暗号blob、鍵をログ・test failure・完了報告へ含めない。
- migrationは再適用可能にし、既存の開発DBを前方更新できるようにする。

## 8. 完了報告に含めるべき内容

- migration名、role属性、対象table、policy式、`FORCE ROW LEVEL SECURITY`の適用結果。
- migration/admin poolとapplication poolの境界、transaction-local contextの設定箇所。
- cross-tenant testで確認したread / insert / update / delete / context resetの結果。
- 既存server統合testと全品質ゲートの実測結果。
- 本番環境で人間が行うruntime login作成・membership・migration適用の残作業。
- 独立検証の判定、commit hash、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-11
- 結果: migration `202607110001_rls_hardening.sql`を追加し、NOLOGIN / NOSUPERUSER / NOBYPASSRLSのgroup role `todori_app`、対象7tableのRLS policyと`FORCE ROW LEVEL SECURITY`を実装した。`tenants` / `tenant_members`のuser fallbackはSELECT専用とし、writeは認証後tenant context一致だけを許可する。
- 接続境界: `DATABASE_MIGRATION_URL`をdirect owner / migration専用、`DATABASE_URL`をpooled non-owner runtime login専用とした。runtime loginはLOGIN / NOSUPERUSER / INHERIT / NOBYPASSRLS、`todori_app`権限利用可、対象table非ownerを接続時に検証し、Neon transaction poolで保持されないsession-level `SET ROLE`には依存しない。
- Context: OPAQUE登録は生成済みuser / tenant、loginは認証済みuserからmembership探索後tenant、session認証はtoken/device確認後user→membership→tenantの順でtransaction-local contextを設定する。全tenant queryは短いcontext付きtransactionへ移した。
- 証拠: `application_role_and_rls_policies_fail_closed_and_isolate_tenants`でgroup/runtime role属性、owner / BYPASSRLS接続拒否、7tableのRLS+FORCE、contextなしfail-closed、複数tenant所属、WHERE省略read分離、history分離、user-only membership昇格拒否、cross-tenant insert/update/delete拒否、commit/rollback後context resetを実Postgresで確認した。serverのauth 1件、RLS 1件、sync v2 14件が成功した。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker/Postgres込み`cargo test --workspace`、bridge release build、`flutter analyze`、`flutter test`（130成功、visual QA harness 1 skip）、hardcoded string check、client boundary check / negative test、`bash -n tool/dev_server.sh`、`git diff --check`が成功した。Rustの既存Keychain実物test 1件と手動performance test 1件はignoredである。
- 環境: sandbox内の初回Docker testはcontainer接続`Operation not permitted`、Flutter analyzeはSDK cache更新`Operation not permitted`で失敗した。いずれも承認付き実行へ切り替え、同じゲートの成功を確認した。
- Docs: DB migration / server deploy runbook、運用ガイド、local dev server scriptをowner direct URLとruntime pooled URLの分離へ更新した。実Neon role作成・migration・デプロイは人間作業として未実施である。
- Commit: `dfd35a3`（`feat(server): RLSによるtenant分離を強化`）。
- 未解決: 実Neon / AWS環境への適用と本番接続確認は人間作業。コード上の未解決事項はなし。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 実装非担当エージェントがpolicy、認証順序、runtime role、Neon transaction pool適合、runbookを監査した。初回の複数tenant可視範囲、user-only membership昇格、認証前tenant context、session-level `SET ROLE`、deploy環境変数不整合を修正し、RLS 1件、auth 1件、sync v2 14件、fmt、clippy、boundary、diff checksを再実行後に最終合格した。
- 検証者: 実装を担当していない検証エージェント。
