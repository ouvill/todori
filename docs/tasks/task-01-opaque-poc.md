# task-01: OPAQUE認証PoC

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

Taskveilは「サーバーがパスワードもタスク内容も知り得ない」ことを掲げるE2EE Todoアプリである。認証にはPAKE（Password-Authenticated Key Exchange）プロトコルの一種である **OPAQUE** を採用し、Rust実装 `opaque-ke` crateを用いる。

OPAQUEの最大の特徴は、ログイン成功時にクライアント側だけが `exportKey` という秘密値を導出できる点である。Taskveilはこの `exportKey` を直接Master Keyとして使うのではなく、HKDFで`KEK_pw`（鍵暗号鍵）を導出し、`KEK_pw` でMaster Key (MK) をラップ（`wrap(MK, KEK_pw)`）してサーバーに保存する。こうすることで、パスワード変更時もMK自体を変えずに済み、タスクデータの再暗号化が不要になる（詳細設計は `docs/03_技術仕様書.md` §4.2〜4.5参照）。

このタスクは、上記フローがRustの `opaque-ke` crateで実際に一気通貫に動作することを証明する **PoC（Proof of Concept）** である。あわせて、OPAQUEログインの多段プロトコル（KE1/KE2/KE3）で発生するサーバー側中間状態を、DynamoDBのようなステートレスなストア（Lambda運用、`docs/03_技術仕様書.md` §1.5, §7.3参照）にバイト列として保存・復元できることを検証する。

このタスクはPoCであり、`server/` へのHTTPエンドポイント実装や実際のDynamoDB接続は行わない。`core/crypto` crate内のテストとして実装し、フローが動作することの証明に専念する。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §1.5（サーバー実行基盤: AWS Lambda、DynamoDBでの中間状態保存）
- `docs/03_技術仕様書.md` §4（暗号設計。特に §4.2 鍵階層図、§4.3 各鍵の定義、§4.5 パスワード変更、§4.7 暗号アルゴリズム・ライブラリ一覧）
- `docs/03_技術仕様書.md` §7.2, §7.3（新規登録・ログインのフロー）
- `core/crypto/src/lib.rs`（crateの現状。OPAQUE統合はこのcrateに追加する設計であることがコメントに明記されている）
- `core/crypto/src/aead.rs`（既存の `encrypt` / `decrypt` API。MKのwrap/unwrapに再利用する）
- `core/crypto/src/kdf.rs`（既存の `derive_key(ikm, info) -> [u8; 32]` API。KEK_pw導出に再利用する）
- `core/crypto/Cargo.toml`、リポジトリルート `Cargo.toml` の `[workspace.dependencies]`（依存追加の作法を確認）

## 3. ゴール

`core/crypto` に `opaque` モジュールを追加し、OPAQUE登録→ログイン→`exportKey`取得→`KEK_pw`導出→Master Keyのwrap/unwrapが一気通貫のテストとして動作し、`cargo test --workspace` で緑になること。

## 4. スコープ

### やること

1. **依存追加**: `opaque-ke` の最新安定版をリポジトリルート `Cargo.toml` の `[workspace.dependencies]` に追加する（`argon2` feature を有効化すること。KSF＝鍵ストレッチング関数にArgon2を使うため）。`core/crypto/Cargo.toml` の `[dependencies]` に `opaque-ke.workspace = true` を追記する。バージョンは執筆時点の最新安定版を選定し、完了報告に正確なバージョン番号を記載すること。
2. **CipherSuite定義**: `core/crypto/src/opaque.rs`（新規ファイル）に、`opaque-ke::CipherSuite` を実装する型（例: `pub struct TaskveilCipherSuite;`）を定義する。以下の選定をコード内ドキュメントコメントで明記すること。
   - OPRF/KeyGroup: Ristretto255ベース（`opaque-ke` が提供するristretto255系の型を使用）
   - KSF（Key Stretching Function）: Argon2
   - ハッシュ関数: SHA-512 または SHA-256（`opaque-ke` の要求する組み合わせに従う。選定理由を1〜2行でコメントに書く）
   - 具体的な型パラメータは `opaque-ke` のドキュメント（`docs.rs`）で該当バージョンのサンプル実装を参照して決定してよい。
3. **登録フローのテスト実装**: `ClientRegistration::start` → （擬似サーバー側）`ServerRegistration::start` → `ClientRegistration::finish` → `ServerRegistration::finish` の一連を関数として実装し、`ServerSetup`（サーバーの長期鍵材料。`ServerSetup::new` で生成）と登録済みの `ServerRegistration` を得る。
4. **ログインフローのテスト実装**: `ClientLogin::start`（KE1）→ `ServerLogin::start`（KE2, `ServerSetup`と登録レコードを利用）→ `ClientLogin::finish`（KE3、ここで `exportKey` が得られる）→ `ServerLogin::finish` の一連を実装する。
5. **exportKey一致の検証**: 登録時にクライアント側で得られる `exportKey`（`ClientRegistrationFinishResult::export_key`）と、ログイン成功時にクライアント側で得られる `exportKey`（`ClientLoginFinishResult::export_key`）が一致することを `assert_eq!` で検証するテストを書く。
6. **KEK_pw導出とMKラップのテスト**: ログインで得た `exportKey` を入力鍵材料 (`ikm`) として、既存の `taskveil_crypto::kdf::derive_key(ikm, info)` を用いて `KEK_pw`（32byte）を導出する。`info` にはバージョン付きの文脈文字列（例: `b"taskveil/kek-pw/v1"`）を用いること。ダミーのMaster Key（32byteの乱数、`OsRng`等で生成）を、既存の `taskveil_crypto::aead::encrypt` / `decrypt` で `KEK_pw` を鍵として wrap / unwrap し、unwrap結果が元のMKと一致することを検証する。
7. **サーバー状態のシリアライズ往復テスト**: `ServerSetup` と、ログイン中間状態（`ServerLogin::start` が返す `ServerLoginStartResult` のうち、次のステップ（`ServerLogin::finish`）に必要な状態。`opaque-ke` の該当バージョンのAPIで「サーバーが次のリクエストまで保持すべき状態」に該当する型を特定すること）について、`serialize()` / `deserialize()`（またはそれに相当するバイト列変換API）を用いてバイト列に変換し、そのバイト列から復元したオブジェクトで後続のプロトコルステップが問題なく完了することをテストで確認する。これはDynamoDBにTTL付きで保存する運用（`docs/03_技術仕様書.md` §1.5）を模したものであり、**単にバイト列に変換できることではなく、復元後も機能することを確認する**のがポイントである。
8. **誤パスワード失敗のテスト**: 登録時と異なるパスワードでログインを試みた場合、`ClientLogin::finish` または `ServerLogin::finish` の段階でエラーになることを確認するテストを書く。
9. 以下のテスト名（または意図の分かる同等の名前）を含めること。
   - `registration_and_login_yield_same_export_key`
   - `wrong_password_fails`
   - `server_setup_roundtrips_through_bytes`
   - `server_login_state_roundtrips_through_bytes`
   - `kek_wraps_and_unwraps_master_key`
10. `core/crypto/src/lib.rs` に `pub mod opaque;` を追加し、必要な型を re-export する（既存の `aead` / `kdf` の re-export スタイルに倣う）。

### やらないこと

- `server/` crateへのHTTPエンドポイント実装（axumルーティング等）は行わない。
- DynamoDBへの実接続（AWS SDK呼び出し）は行わない。シリアライズ/デシリアライズの往復のみを検証する。
- Flutter (`app/`) との連携は行わない。
- パスワード変更フロー・リカバリーキーフローの実装（設計上はラップの付け替えのみで新規性がないため、このPoCでは不要）。
- `core/domain` や `core/storage` の変更。

## 5. 実装手順（例）

1. `cargo search opaque-ke` または `docs.rs/opaque-ke` で最新安定版バージョンを確認し、`argon2` featureが利用可能か確認する。
2. リポジトリルート `Cargo.toml` の `[workspace.dependencies]` に追記する。

   ```toml
   opaque-ke = { version = "<最新安定版>", features = ["argon2"] }
   ```

3. `core/crypto/Cargo.toml` に追記する。

   ```toml
   opaque-ke.workspace = true
   ```

4. `core/crypto/src/opaque.rs` を新規作成し、`CipherSuite` 実装・登録/ログインのヘルパー関数・テストを実装する。
5. `core/crypto/src/lib.rs` を編集し `pub mod opaque;` を追加する。
6. `cargo test -p taskveil-crypto` でこのcrate単体のテストを繰り返し実行しながら実装する。
7. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行し全体の品質ゲートを確認する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する
- [ ] `cargo test --workspace` が全テスト成功する
- [ ] `cargo test -p taskveil-crypto opaque::` で本タスクの新規テストがすべて実行され成功する
- [ ] 上記5.のテスト名（または同等の意図のテスト）がすべて存在し成功する
- [ ] `core/crypto/src/opaque.rs` 内のCipherSuite定義部分に、選定したOPRF/KSF/ハッシュ関数とその理由がコメントで明記されている

## 7. 制約・注意事項

- `opaque-ke` のAPIはバージョンによって型名・メソッド名が変わる。本指示書は概念的なフロー（登録→ログイン→exportKey→KEK→wrap）を規定するものであり、具体的なメソッドシグネチャは選定したバージョンの公式ドキュメント／サンプルコードに従うこと。
- 乱数生成には `opaque-ke` が要求するRNG traitを満たす実装（多くの場合 `rand::rngs::OsRng` または `rand_core::OsRng`。バージョン不整合に注意）を用いること。
- パスワードやexportKeyなどの秘密情報をテストコード内で `println!`/`dbg!` 等でログ出力しないこと。
- Argon2のパラメータ（メモリコスト等）はテスト実行時間に直結する。テストが極端に遅くなる場合は、テスト用に軽量なパラメータを明示的に指定してよい（本番用パラメータとは別に、コード内コメントで「テスト用に緩めている」旨を明記すること）。

## 8. 完了報告に含めるべき内容

- 採用した `opaque-ke` の正確なバージョン番号
- 選定した `CipherSuite`（OPRF/KeyGroup, KSF, ハッシュ関数）の具体的な型・パラメータ
- `ServerSetup` および サーバー側ログイン中間状態をシリアライズした際の実測バイトサイズ（DynamoDBのアイテム設計・TTL設計の入力になるため）
- Argon2のデフォルトパラメータ値と、本番投入前に調整が必要かどうかの所見
- 実装中にハマった点・`opaque-ke` のAPI仕様で分かりにくかった点
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `core/crypto/src/opaque.rs` を追加し、`core/crypto/src/lib.rs` から `pub mod opaque;` と `TaskveilCipherSuite` のre-exportを追加した。
- `opaque-ke` は最新pre-releaseではなく、安定版として `3.0.0` を採用した。`argon2` featureを有効化した。
- 登録、ログイン、exportKey一致、KEK_pw導出、Master Key wrap/unwrap、誤パスワード失敗、サーバー状態のbytes往復をテストで確認した。

### CipherSuite

| 項目 | 採用値 |
|---|---|
| OPRF | `opaque_ke::Ristretto255` |
| KeyGroup | `opaque_ke::Ristretto255` |
| KeyExchange | `opaque_ke::key_exchange::tripledh::TripleDh` |
| KSF | `argon2::Argon2<'static>` |
| Hash | Ristretto255 VOPRF ciphersuiteが選択するSHA-512系hash |

### 実測値

| 対象 | サイズ |
|---|---:|
| `ServerSetup<TaskveilCipherSuite>` serialize結果 | 128 bytes |
| `ServerLogin<TaskveilCipherSuite>` state serialize結果 | 192 bytes |

### Argon2パラメータ

- `argon2 0.5.3` のデフォルトは `m_cost = 19 * 1024 KiB`, `t_cost = 2`, `p_cost = 1`, output length 32 bytes。
- テストではPoCの実行時間を抑えるため、明示的に `m_cost = 512 KiB`, `t_cost = 1`, `p_cost = 1` を使用した。
- 本番投入前にはiOS/Android実機でログイン体感、発熱、バッテリー影響を計測し、端末クラス別に本番パラメータを決める必要がある。

### ハマった点

- `opaque-ke 3.0.0` では `key_exchange::traits::{Serialize, Deserialize}` は公開APIではない。`ServerSetup` / `ServerLogin` などのinherent `serialize()` / `deserialize()` を使う必要があった。
- crates.ioの検索結果では `4.1.0-pre.2` が先頭に出たが、タスク要件の「最新安定版」に合わせて `3.0.0` を採用した。

### 検証

- `cargo test -p taskveil-crypto opaque::` 成功。
- `cargo test --workspace` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。

### 未解決事項

- task-01はPhase 1では直接使わない。Phase 2でサーバーAPIに組み込む際、技術仕様書§1.5の方針に合わせてOPAQUE中間状態の保存先をPostgres ephemeral tableとして設計する必要がある。
