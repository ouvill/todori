# task-70: P2-M2 同期サーバー

> ステータス: 未着手
> 作成日: 2026-07-08

## 1. 背景とコンテキスト

Phase 2 P2-M2として、E2EE同期のサーバー中核を `server/` crate に実装する。対象はPostgresスキーマ、OPAQUE登録/ログインAPI、セッショントークン、tenant認可、push/pull API、`tenant_seq` によるseq採番、`sync_records_history` 退避、§6.6のサーバー不変条件である。

TodoriのサーバーはE2EEデータの中身を解釈せず、暗号blobと最小限の同期メタデータだけを扱う。同期はADR-005の「最新状態方式 + クライアント再push」であり、サーバーは `incoming.hlc > stored.hlc` の場合だけ最新行を更新する。task-69で見つかった「再push時にrecord HLCが同値になり得る」問題は、クライアントが再push前に必ずHLCをtickして新しい `op.hlc` で送る規約として `docs/03_技術仕様書.md` §6.4へ本タスク内で1文追記する。

`server/` は最終的にAWS Lambda上で動かすが、本タスクではローカルHTTPサーバーとして起動できるところまでを実装する。Lambdaアダプタ層は将来差し替えられる薄いバイナリ境界に留め、ハンドラとサービス層はLambdaイベントに依存しない純粋関数寄りの構成にする。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M2
- `docs/03_技術仕様書.md` §1.5（OPAQUE中間状態、Postgres ephemeral）、§2（Lambda/Neon構成）、§3（サーバーデータモデル）、§6（同期プロトコル、push/pull、seq採番、§6.6不変条件）、§7（アカウントフロー）
- `docs/05_設計判断記録.md` ADR-003、ADR-005、ADR-008
- `docs/tasks/task-01-opaque-poc.md`（`opaque-ke 3.0.0`、Argon2、`ServerSetup` / `ServerLogin` bytes往復の学び）
- `docs/tasks/task-69-sync-foundation.md` の `## 9. 完了報告`（HLC固定幅エンコード、blob 64KB、再push HLC同値問題）
- `server/Cargo.toml`
- `server/src/main.rs`
- `server/src/routes/*.rs`
- `core/crypto/src/opaque.rs`
- `core/sync/src/hlc.rs`
- `core/sync/src/envelope.rs`
- ルート `Cargo.toml`

## 3. ゴール

- `server/` を `axum` + `sqlx(Postgres)` + `tokio` のAPIサーバーとして実装し、ローカルで `cargo run -p todori-server` できること。
- `server/migrations` にPostgres用sqlx migrationを追加し、users/devices/tenants相当、セッション、OPAQUE ephemeral、`sync_records`、`tenant_seq`、`sync_records_history` を作成できること。
- `opaque-ke 3.0.0` による登録/ログインの2往復エンドポイントを実装し、中間状態をPostgres ephemeral tableへ短期保存し、consume時に削除すること。
- OPAQUE完了時にランダムなセッショントークンを発行し、DBにはハッシュと有効期限だけを保存すること。
- `POST /v1/tenants/{tenant_id}/push` と `GET /v1/tenants/{tenant_id}/pull?since=&limit=` を実装し、§6.4/§6.6/ADR-005の同期契約を統合テストで固定すること。
- testcontainers-modulesのPostgresで、OPAQUE、push/pull、seq順序、冪等性、不変条件、tenant分離、ephemeral掃除を実DBで検証すること。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- ルート `Cargo.toml`
- `server/Cargo.toml`
- `server/src/main.rs`
- `server/src/lib.rs`
- `server/src/routes/*.rs`
- `server/src/auth/*.rs`
- `server/src/sync/*.rs`
- `server/src/db/*.rs`
- `server/migrations/*.sql`
- `server/tests/*.rs`
- `docs/03_技術仕様書.md`
- `docs/tasks/task-70-sync-server.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `server/` の構成を、ルーター構築、AppState、DB pool、リポジトリ、サービス関数、HTTP DTOに分ける。`main.rs` はローカル起動用の薄いバイナリ境界にする。
2. Rust依存はworkspace集約で追加する。想定は `sqlx`（postgres/runtime-tokio-rustls/uuid/chrono/migrate等）、`testcontainers-modules`（postgres）、`base64` または同等のopaque message表現、セッショントークン用の乱数/ハッシュ補助である。
3. `server/migrations` にPostgresスキーマを実装する。最低限、`users`、`devices`、`tenants`（個人tenantを表現できること）、セッション、OPAQUE登録/ログインephemeral、`sync_records`、`tenant_seq`、`sync_records_history` を含める。Org共有・課金用の詳細テーブルは本タスクで実動作させないが、将来拡張を妨げない列設計にする。
4. 既存のTurso前提TODO（`routes/tenant.rs` / `routes/sync_token.rs` 等）をPostgres/sqlx前提へ置換または撤去する。
5. OPAQUE登録APIを2往復で実装する。中間状態は `expires_at` 付きephemeral tableへ保存し、finish/consume時に同一トランザクション内で削除する。期限切れ・再利用は失敗させる。
6. OPAQUEログインAPIを2往復で実装する。`opaque-ke 3.0.0` とtask-01のCipherSuite/bytes往復の知見を使い、誤パスワード、期限切れ、state再利用をテストする。`exportKey` はクライアントだけが得る秘密値であり、サーバーへ保存・ログ出力しない。
7. OPAQUE完了時にセッショントークンを発行する。平文トークンはレスポンスで一度だけ返し、DBにはハッシュ、有効期限、user/device帰属を保存する。push/pullでは `Authorization: Bearer ...` を必須にし、リクエストごとにsession/device revoked/tenant所属を検証する。
8. push APIを実装する。bodyは§6.4のops配列 `{record_id, collection, hlc, deleted, blob}` とし、blobは64KB上限、ops件数は明示的な上限を持つ。`core/sync::Hlc::decode` と未来5分判定を利用する。
9. push採用時は1トランザクション内で `tenant_seq` 行を `UPDATE ... RETURNING` してseq採番し、既存行がある場合は旧行を `sync_records_history` へ退避してからupsertする。`incoming.hlc > stored.hlc` のみ採用し、低いHLCはsuperseded、同一HLCかつ同一blobは冪等no-op、同一HLCかつ異なるblobはプロトコル違反として拒否する。
10. pull APIを実装する。`GET /v1/tenants/{tenant_id}/pull?since={seq}&limit={n}` は `{records, next_since, has_more}` を返し、初回 `since=0`、limit上限、seq昇順、エコー除外なしを守る。pull成功時はdeviceの `last_pull_at` を更新する。
11. `docs/03_技術仕様書.md` §6.4へ、再push時はクライアントが必ずHLCをtickして新しい `op.hlc` で送る、という規約を1文だけ追記する。本タスクは共通規約の「docs/03不変更」の明示例外である。
12. testcontainers-modulesのPostgresで統合テストを実装する。Docker前提でよい。migration適用、OPAQUE登録/ログイン、session認証、push/pull往復、seq順序、冪等性、§6.6違反拒否、tenant分離、revoked device拒否、ephemeral期限切れ掃除をカバーする。

### やらないこと

- AWS/ECR/Lambda/Neon本番環境へのデプロイ、クレデンシャル投入、WAF/API Gateway/CloudFront設定。
- Lambda Web Adapterや`lambda_http`等を使った実Lambda起動。本タスクでは将来差し替え可能な境界設計とローカル起動までに留める。
- Flutter UI、FRB、Dart client、クライアント同期ループの接続。
- P2-M3のMK生成、`wrap(MK, KEK_pw)`、DEK、Recovery Key、デバイス追加フローの完成。
- 課金Webhook、実課金判定、Org共有API。push/pullの認可境界は実装するが、課金は将来フックまたは常時許可の最小実装に留める。
- 削除同期の最終意味論、tombstone GC、`sync_records_history` の30日削除ジョブ。`deleted` flagの保存・転送だけを扱う。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/05_設計判断記録.md` の変更。
- git commit。

## 5. 実装手順（例）

1. `git status --short` で作業前状態を確認する。
2. 事前に読むべきファイルを読み、OPAQUE中間状態、Postgres一本化、seq採番、再push規約、§6.6不変条件を確認する。
3. ルート `Cargo.toml` の `[workspace.dependencies]` と `server/Cargo.toml` に必要依存を追加する。`sqlx::query!` 系を使う場合はoffline metadataや`DATABASE_URL`要件を増やすため、まずはruntime checked queryを優先してよい。
4. `server/src/lib.rs` を追加し、`build_router(app_state) -> Router`、DB pool初期化、migration実行、サービス関数を `main.rs` から分離する。
5. `server/migrations` を作り、schemaを先に固める。migration testで全テーブル、制約、index、`tenant_seq` 初期化、history退避に必要な列を検証する。
6. OPAQUE登録/ログインを実装する。opaque messageはHTTP JSON上ではbase64文字列として扱い、Rust内部ではopaque-keのbytesへ変換する。
7. セッション発行と認証extractor/middlewareを実装する。ログにはtoken hashの一部も含めず、request idやuser/tenant id等の非秘密メタデータに留める。
8. pushサービスをHTTPから独立した関数として実装し、単体/統合テストでaccepted、superseded、no-op、same-HLC-different-blob rejectを固定する。
9. pullサービスを実装し、`since` / `limit` / `next_since` / `has_more` の境界値をテストする。
10. `cleanup_expired_opaque_states(pool, now)` のような関数を用意し、期限切れephemeralを削除できることをテストする。EventBridge Schedulerで呼ぶ実ジョブ化はスコープ外。
11. `docs/03_技術仕様書.md` §6.4へ再push HLC tick規約を1文追記する。
12. `cargo test -p todori-server`、`cargo test --workspace`、品質ゲートを実行する。
13. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを完了状態へ更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと（ただし、本指示書で明示した `docs/03_技術仕様書.md` §6.4の1文追記は例外）。

タスク固有の受け入れ基準:

- [ ] `server/migrations` のPostgres schemaが、users/devices/tenants相当、sessions、OPAQUE ephemeral、`sync_records`、`tenant_seq`、`sync_records_history` を作成し、testcontainers Postgres上でmigration testが成功している。
- [ ] `server/` が `axum` + `sqlx(Postgres)` + `tokio` 構成でローカル起動でき、`/health` とv1 routerが `main.rs` から分離された再利用可能なルーター/サービス層で構成されている。
- [ ] OPAQUE登録/ログインの2往復APIが `opaque-ke 3.0.0` で動作し、登録、ログイン、誤パスワード失敗、期限切れ、state再利用不可を統合テストで確認している。
- [ ] OPAQUE中間状態はPostgres ephemeral tableに保存され、finish/consume時に削除され、期限切れ掃除関数のテストがある。
- [ ] OPAQUE完了時にランダムセッショントークンを発行し、DBにはハッシュと有効期限だけを保存し、push/pullはBearer token必須である。
- [ ] push APIがaccepted/superseded/no-op/same-HLC-different-blob rejectを返し、採用時のseq採番は `tenant_seq` の `UPDATE ... RETURNING` を同一トランザクション内で使っている。
- [ ] push採用による上書き時、旧 `sync_records` 行が `sync_records_history` へ退避され、author_user_idが記録される。
- [ ] pull APIが `since`、`limit`、`next_since`、`has_more`、初回 `since=0`、seq昇順、エコー除外なしを満たす。
- [ ] §6.6不変条件として、blob 64KB上限、push batch上限、pull limit上限、HLC未来5分超拒否、物理DELETE APIなしをテストで確認している。
- [ ] tenant分離、他tenantアクセス拒否、revoked deviceのpush/pull拒否を統合テストで確認している。
- [ ] 秘密情報（パスワード、exportKey、セッショントークン平文、OPAQUE state bytes）をログ・`dbg!`・`println!` に出していないことをコードレビュー項目として完了報告に記録している。
- [ ] `docs/03_技術仕様書.md` §6.4に再push HLC tick規約の1文が追加され、`docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/05_設計判断記録.md` は変更されていない。

## 7. 制約・注意事項

- サーバーは暗号blobの中身を読まない。`{fields, field_hlcs}` の検証やマージはクライアント側の責務であり、サーバーはrecord_id、collection、hlc、seq、deleted、blobサイズ、時刻系メタデータだけを扱う。
- `sync_records` に `device_id` カラムを追加しない。更新元デバイス識別はHLCのnode成分とsession/device認可で扱い、historyのauthor_user_idだけを保持する。
- `seq` をHLCやPostgres bigserialで代用しない。ADR-005どおり、`tenant_seq` 行の `UPDATE ... RETURNING` によるテナント単位直列化を使う。
- Neonのプーラーはトランザクションモード前提である。advisory lock、LISTEN/NOTIFY、セッション状態に依存するPostgres機能は使わない。
- OPAQUE登録/ログインは仕様外の独自拡張をしない。中間状態はephemeral tableで期限管理し、consume時に削除する。
- セッショントークンは認証用のランダムtokenであり、同期プロトコルの冪等性キーや暗号鍵として使わない。
- 再pushはクライアントがHLCをtickした新しい `op.hlc` で送る。サーバー側の採用条件は `incoming.hlc > stored.hlc` のまま維持する。
- 同一HLCかつ異なるblobは「マージ済み再push」ではなくプロトコル違反として扱う。正しい再pushは新HLCで送られる。
- 削除同期の最終意味論はP2-M5へ送る。本タスクでは `deleted` flagを保存・転送するだけで、GCや復活/削除競合ルールを確定しない。
- 課金・Org共有はスコープ外である。将来のリクエスト単位検証を入れられるサービス境界は用意してよいが、課金判定やOrgメンバーAPIを実装しない。
- testcontainersはDocker daemonが動いている前提でよい。実行不能な場合は環境起因として完了報告に明記する。
- `flutter_rust_bridge_codegen` は実行しない。Flutter/Dart/FRBに触れない。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 実装したHTTP endpoint一覧とrequest/response DTO概要
- 追加したPostgres migrationと各テーブル/主要index/制約の概要
- OPAQUE実装の詳細（CipherSuite、ephemeral table、expires_at、consume削除、期限切れ掃除）
- セッショントークンの生成方式、保存形式（ハッシュ）、有効期限、認証フロー
- push実装の詳細（accepted/superseded/no-op/reject、seq採番トランザクション、history退避、HLC未来判定、上限値）
- pull実装の詳細（since/limit/next_since/has_more、device last_pull_at更新）
- tenant分離・revoked device拒否・他tenantアクセス拒否のテスト名
- testcontainers Postgres統合テストの対象と実行結果
- 新規依存crate一覧と用途
- `docs/03_技術仕様書.md` §6.4へ追加した文言の要約
- 秘密情報ログ禁止の確認結果
- 品質ゲート実行結果
- 変更ファイル一覧
- 未解決事項（削除同期、課金、Org共有、Lambda/Neon実デプロイなど。無い場合も「なし」と明記）
