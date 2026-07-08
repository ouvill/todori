# task-71: P2-M3 鍵階層とアカウント接続

> ステータス: 未着手
> 作成日: 2026-07-08

## 1. 背景とコンテキスト

Phase 2 P2-M3として、P2-M2で実装済みのOPAQUE/セッションAPIと、`docs/03_技術仕様書.md` §4の鍵階層をクライアントへ接続する。対象はクライアント側OPAQUEフロー、MK/KEK/DEK/Recovery Keyの生成・ラップ・復元、デバイス登録、ローカルKeychain保存、FRB公開、Flutterの最小アカウント画面である。

Todoriの鍵設計は `docs/03_技術仕様書.md` §4を唯一の正とする。独自の鍵階層を発明してはならない。平文MKは永続保存せずメモリ上だけに置く。ローカル永続化するMK復元材料は `wrap(MK, DK)` であり、Keychain itemとして保存する場合も平文MKではなくラップ済み値を保存する。セッショントークンもKeychainへ保存し、Device Keyとはservice名を分離する。

P2-M3は同期ループそのものではない。登録/ログインで鍵が復元でき、以後P2-M4の同期エンジンがDEKを使える状態までを作る。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/08_Phase2計画書.md` P2-M3
- `docs/03_技術仕様書.md` §1.5（OPAQUE中間状態、Postgres保存）、§3（users/devices/tenantとラップ済み鍵の置き場）、§4（鍵階層、各鍵の定義、保存場所、レコード暗号化方式）、§5.3（ローカルDB鍵）、§7（アカウントフロー）
- `docs/05_設計判断記録.md` ADR-003、ADR-007、ADR-008
- `docs/tasks/task-01-opaque-poc.md` の `## 9. 完了報告`
- `docs/tasks/task-64-keychain-device-key.md` の `## 9. 完了報告`
- `docs/tasks/task-69-sync-foundation.md` の `## 9. 完了報告`
- `docs/tasks/task-70-sync-server.md` の `## 9. 完了報告`
- `server/src/auth.rs`
- `server/src/routes/auth.rs`
- `server/src/db.rs`
- `server/migrations/202607080001_sync_server.sql`
- `core/crypto/src/aead.rs`
- `core/crypto/src/kdf.rs`
- `core/crypto/src/opaque.rs`
- `core/crypto/src/device_key.rs`
- `core/sync/src/envelope.rs`
- `app/rust/src/api.rs`
- `app/rust/src/dev_key_store.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/router.dart`
- `app/lib/src/screens/lists_screen.dart`

## 3. ゴール

- `core/sync`（または同等の共有Rust crate）に、`opaque-ke 3.0.0` のクライアント登録/ログインフローと `reqwest(rustls)` HTTP clientを実装し、Flutter/CLI/MCPが再利用できる形にすること。
- 登録時にMK、Recovery Key、User X25519鍵ペア、個人Tenant Root DEK、既存個人リスト用List DEKを生成し、`docs/03` §4どおりにラップしてサーバー/ローカルへ保存すること。
- ログイン時にOPAQUE exportKey由来KEKで `wrap(MK, KEK_pw)` を復号し、MK、User X25519秘密鍵、Tenant Root DEK、List DEKを復元できること。
- 新デバイスログイン時に `devices` 表対応のデバイスメタデータを登録し、ローカルDevice Keyで `wrap(MK, DK)` を作ってKeychainへ保存すること。
- セッショントークンと `wrap(MK, DK)` をKeychainへ保存し、service名をDevice Keyとは分離すること。平文MK/KEK/DEK/exportKeyはログ出力せず、メモリ上では `zeroize` で破棄すること。
- FRBに `register` / `login` / `logout` / `session state` 系APIを公開すること。MK/KEK/DEK等の鍵バイト列をDart境界へ出さないこと。
- FlutterにLists画面overflowから「アカウント」導線を追加し、未ログイン時の登録/ログイン、ログイン済み時のメール表示/ログアウト、デバッグ用サーバーURL設定を最小UIとして実装すること。
- testcontainers Postgres + 実サーバー起動 + Rust clientで、登録→ログアウト→ログイン→MK復元の一気通貫統合テストを通すこと。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- ルート `Cargo.toml`
- `core/crypto/Cargo.toml`
- `core/crypto/src/*.rs`
- `core/sync/Cargo.toml`
- `core/sync/src/*.rs`
- `server/Cargo.toml`
- `server/src/auth.rs`
- `server/src/routes/auth.rs`
- `server/src/db.rs`
- `server/migrations/*.sql`
- `server/tests/*.rs`
- `app/rust/Cargo.toml`
- `app/rust/src/api.rs`
- `app/rust/src/dev_key_store.rs`
- `app/lib/src/core/bridge_service.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/router.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/account_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/test/**/*`
- `docs/tasks/task-71-key-hierarchy-account.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `git status --short` で作業前状態を確認する。未コミット変更があれば、タスクに関係するものだけを慎重に読み、無関係な変更は触らない。
2. Rust依存はworkspace集約で追加する。想定は `reqwest`（rustls、default-features off）、`zeroize`、必要に応じて `x25519-dalek`、Recovery Key生成用crate、base64/uuid補助である。既存依存で足りるものは追加しない。
3. `core/crypto` に鍵階層用の小さなプリミティブを追加する。MK/Tenant Root DEK/List DEKは32byte乱数、KEK_pwはOPAQUE exportKeyからHKDF-SHA256、Recovery Key由来鍵も固定context付きHKDFで32byteへ導出する。wrap/unwrapは既存AEADを使い、用途別AAD/contextを定数化して互換性テストで固定する。
4. `core/sync` にaccount client moduleを追加する。OPAQUE client start/finish、register/login/logout/session refreshに必要なHTTP DTO、base64変換、server URL設定、セッション保持抽象をRust側に置く。ネットワークはDartではなく `reqwest(rustls)` で行う。
5. サーバーmigrationを追加し、`docs/03` §4.3/§4.9のサーバー保存物を保持できるようにする。最低限、`wrap(MK, KEK_pw)`、`wrap(MK, RecoveryKey)`、User X25519公開鍵、`wrap(SK, MK)`、個人Tenant Root DEKのwrap、個人List DEKのwrapを保存/取得できる列またはテーブルを用意する。
6. OPAQUE登録finishを拡張し、クライアントがregistration finish messageと同時に鍵payloadを送れるようにする。サーバーはラップ済み鍵と公開鍵だけを保存し、パスワード、exportKey、MK、KEK、DEK、Recovery Key平文を受け取らない。
7. OPAQUEログインfinishを拡張し、セッションレスポンスに復号に必要なラップ済み鍵bundleを返す。クライアントはexportKey由来KEKでMKを復元し、MKでUser X25519秘密鍵/Tenant Root DEK/List DEKを復元する。
8. デバイス登録を `docs/03` §3.2/§7.3に合わせる。ログインfinish時にdevice_nameと必要ならdevice public_keyを保存し、サーバーには `wrap(MK, DK)` を送らない。`wrap(MK, DK)` はローカルKeychain保存とする。
9. `app/rust/src/dev_key_store.rs` のtask-64パターンを一般化し、Device Key、session token、local wrapped MK用にservice名を分離したKeychain storeを用意する。Flutter test時は既存と同様にファイル/メモリ系fallbackを使い、実Keychainへ触れない。
10. FRB公開APIを追加する。例: `accountRegister(email, password, serverUrl?, deviceName?)`、`accountLogin(...)`、`accountLogout()`、`getAccountSessionState()`、`get/setSyncServerUrl()`。関数名は既存Dart namingに合わせる。Rust API変更後はリポジトリルートで `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` を実行し、生成物は手編集しない。
11. Flutter UIを追加する。`/account` route、`AccountScreen`、Riverpod provider/fake、en/ja ARBを実装する。Lists画面右上overflowに「アカウント」導線を置く。未ログイン時は登録/ログインフォーム、ログイン済み時はメール+ログアウトを表示する。Recovery Keyは登録完了後に一度だけ表示し、画面遷移後に再表示できないようにする。
12. デバッグ用サーバーURLをsettings storeに保存する。キー名は既存 `ui_mode` と衝突しない `sync_server_url` 等にし、未設定時は `http://localhost:3000` を既定値にする。通常利用時に秘密情報をsettingsへ保存しない。
13. Rust統合テストを追加する。testcontainers Postgresにmigrationを当て、実axum serverをローカルportで起動し、Rust clientから登録→セッション確認→ログアウト→ログイン→同一MK復元を検証する。誤パスワード、失効セッション、誤鍵unwrap失敗も含める。
14. Flutter widget testをfake bridgeで追加する。未ログイン画面、登録成功後のRecovery Key一度表示、ログイン済みメール表示、ログアウト後の未ログイン復帰、サーバーURL設定の表示/保存を確認する。
15. 秘密情報ログ禁止を確認する。`println!`、`dbg!`、`tracing`、Flutter error表示にパスワード、session token、MK、KEK、DEK、DK、exportKey、Recovery Key平文を含めない。

### やらないこと

- P2-M4の同期ループ、push/pullの自動実行、outbox ACK、pull復号マージ、UI invalidate連携。
- Recovery Keyによるパスワード復旧UX完全版。P2-M3では登録時生成、一度だけ表示、`wrap(MK, RecoveryKey)` 保存までとする。
- 複数デバイス管理UI、デバイス一覧、デバイス失効UI。
- Organization共有、sealed boxによるOrg DEK配布、Orgメンバー管理、Org DEKローテーション。
- AWS/ECR/Lambda/Neon本番デプロイ、クレデンシャル投入、WAF/API Gateway/CloudFront設定。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/05_設計判断記録.md` の変更。
- git commit。

## 5. 実装手順（例）

1. 指定ファイルを読み、`docs/03` §4.3の各鍵の保存先、§4.8のDEK対応、§7.2/§7.3の登録/ログイン順序をメモする。
2. サーバーmigrationの形を先に決める。ユーザー単位鍵、テナント単位鍵、リスト単位鍵を混同しない。個人リストのList DEK wrapはlist_id単位で取得できる必要がある。
3. `core/crypto` に鍵生成・KEK導出・wrap/unwrap・Recovery Key生成の単体テストを追加する。roundtrip、誤鍵失敗、AAD/context違い失敗、zeroize対象型の破棄をテストまたはコードレビュー項目で固定する。
4. `core/sync` のaccount clientでOPAQUE登録/ログインを実装する。task-01のPoCとtask-70のHTTP DTOを照合し、exportKeyはクライアント内部だけで使う。
5. サーバーのregister/login finish DTOを拡張し、testcontainers上でラップ済み鍵の保存/返却を検証する。
6. Keychain storeを汎用化する。service名は少なくとも `dev.todori.todori.device-key`、`dev.todori.todori.session-token`、`dev.todori.todori.master-key-wrap` 相当で分離する。命名はコード内定数化し、秘密値をログに出さない。
7. `app/rust/src/api.rs` へFRB APIを追加する。`AccountSessionStateDto` のようなDTOはメール、user_id、tenant_id、device_id、logged_in程度に留め、鍵バイト列やセッショントークン平文を返さない。Recovery Keyだけは登録直後の一度表示用文字列として返してよい。
8. FRB生成を実行し、Dart bridge/fakeへメソッドを追加する。
9. Flutterのaccount providerと画面を追加する。エラー表示は安全な汎用文言にし、サーバーからの内部エラーや秘密情報をそのまま表示しない。
10. Lists画面の右上にoverflow menuを追加し、「アカウント」から `/account` へ遷移させる。icon-only controlはtooltip/semanticsを付ける。
11. Rust統合テストとFlutter widget testを追加し、品質ゲートを実行する。ローカルport bindやDockerが環境制約で失敗した場合は、実装とテストは残し、完了報告へ環境起因として明記する。
12. 本ファイルへ `## 9. 完了報告` を追記し、README/BACKLOGを完了状態へ更新する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `core/crypto` にMK/KEK_pw/Recovery Key/User X25519鍵/List DEK/Tenant Root DEKの生成・wrap/unwrap helperがあり、roundtrip、誤鍵失敗、AAD/context違い失敗の単体テストがある。
- [ ] `core/sync` または共有Rust crateに `opaque-ke 3.0.0` クライアントフローと `reqwest(rustls)` account clientがあり、Dart側HTTP実装なしで登録/ログインできる。
- [ ] サーバーmigration/APIが `wrap(MK, KEK_pw)`、`wrap(MK, RecoveryKey)`、User X25519公開鍵、`wrap(SK, MK)`、個人Tenant Root DEK wrap、個人List DEK wrapを保存/返却でき、平文鍵を受け取らない。
- [ ] 登録時にMK、Recovery Key、User X25519鍵ペア、個人Tenant Root DEK、既存個人リスト用List DEKが生成され、`docs/03` §4.3/§4.8どおりの保存先にラップ済みで配置される。
- [ ] ログイン時にOPAQUE exportKey由来KEKで同一MKを復元でき、User X25519秘密鍵、Tenant Root DEK、List DEKのunwrapまでテストされている。
- [ ] 新デバイスログイン時にserver `devices` 行が作成され、`wrap(MK, DK)` はサーバーへ送られずローカルKeychainへ保存される。
- [ ] Keychain service名がDevice Key、session token、local wrapped MKで分離され、ログアウト時にsession tokenとメモリ上の鍵状態が破棄される。
- [ ] FRBのregister/login/logout/session state APIが追加され、MK/KEK/DEK/DK/exportKey/セッショントークン平文をDart境界へ返さない。Recovery Keyは登録直後の一度表示だけに限定される。
- [ ] FlutterにLists画面overflowの「アカウント」導線、`/account` route、未ログイン/ログイン済み/ログアウト/サーバーURL設定の最小UIがあり、UI文字列はen/ja ARB化されている。
- [ ] testcontainers Postgres + 実axum server + Rust account clientで、登録→ログアウト→ログイン→MK復元、誤パスワード、失効セッション、誤鍵unwrap失敗の統合テストが成功している。
- [ ] Flutter widget testがfake bridgeで、未ログイン表示、登録成功後のRecovery Key一度表示、ログイン済みメール表示、ログアウト復帰、サーバーURL設定を確認している。
- [ ] 秘密情報ログ禁止の確認結果（対象: password、session token、MK、KEK、DEK、DK、exportKey、Recovery Key平文、OPAQUE state bytes）を完了報告に記録している。

## 7. 制約・注意事項

- `docs/03_技術仕様書.md` §4を優先する。平文MKは永続保存しない。Keychainに保存するローカルMK材料は `wrap(MK, DK)` であり、平文MKではない。
- SQLCipherのローカルDB鍵は従来どおりDK由来の `todori/local-db-key/v1` から導出する。アカウント登録時にPRAGMA rekeyしない。
- exportKeyをMKとして使わない。exportKeyはKEK_pw導出だけに使い、ログイン処理後にzeroizeする。
- MKは不変である。パスワード変更は本タスク外だが、将来のために `wrap(MK, KEK_pw)` を差し替えられるデータ配置にする。
- List DEKとTenant Root DEKを混同しない。tasks/comments/remindersはList DEK、tags/templates/schedules/timer_sessionsはTenant Root DEKである。
- サーバーは暗号blobや鍵の平文を解釈しない。ラップ済み鍵と公開鍵、device metadata、session metadataだけを扱う。
- `devices.public_key` は将来のデバイス単位鍵配布用予約フィールドである。Org共有のUser X25519鍵ペアとは役割が違うため、混同しない。
- Recovery Key平文はサーバーへ送らない。端末にも保存しない。登録完了画面で一度だけ表示し、完了後は再表示しない。
- セッショントークンは認証用であり、暗号鍵やHKDF入力に使わない。
- Flutter/Dartのフォーム入力としてパスワードは一時的にDartを通るが、鍵バイト列はDartへ出さない。Rust側で扱う秘密byte/stringは可能な限り `zeroize` 対応型で保持する。
- `flutter_rust_bridge_codegen` は `app/rust/src/api.rs` 変更後に必ず実行する。生成物は手編集しない。
- testcontainersはDocker daemonが動いている前提でよい。ローカルsocket bindがsandboxで禁止される場合は、テスト実行不能の理由を完了報告に明記する。

## 8. 完了報告に含めるべき内容

- 作業日、読んだファイル
- 追加/変更したRust依存crateと用途
- 鍵階層実装の要約（MK、KEK_pw、Recovery Key、User X25519鍵、Tenant Root DEK、List DEK、各wrapの保存先）
- 追加したserver migrationと、ラップ済み鍵/公開鍵/device/sessionの保存先
- 登録フローの詳細（OPAQUE client、exportKey、MK生成、Recovery Key一度表示、server payload、local Keychain保存）
- ログイン/新デバイスフローの詳細（MK復元、User秘密鍵/DEK unwrap、device登録、`wrap(MK, DK)` local保存）
- logout/session stateの挙動（server revoke、Keychain削除対象、メモリ鍵破棄、ローカルDB/Device Keyを消さないこと）
- FRB公開API一覧とDTO概要（Dart境界へ返さない秘密値を明記）
- Flutter UI変更、追加route、追加ARB key、widget test名
- testcontainers + 実サーバーRust統合テストの対象と実行結果
- zeroize適用箇所と秘密情報ログ禁止の確認結果
- FRB再生成の実行結果
- 品質ゲート実行結果
- 変更ファイル一覧
- 未解決事項（同期ループ、Recovery UX完全版、複数デバイス管理UI、Org共有、実デプロイ等。無い場合も「なし」と明記）
