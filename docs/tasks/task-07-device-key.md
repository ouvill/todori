# task-07: Device Key生成・キーチェーン抽象・SQLCipher鍵導出

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM1「コア層完成」は、M1-04「DK生成、OSキーチェーン保存、SQLCipher鍵導出の抽象を定義する」を定義している。このタスクは同項目に対応する。

仕様の根拠は次のとおりである。

- `docs/03_技術仕様書.md` §4.3: Device Key (DK) は32byte乱数。初回起動時に生成し、iOS: Keychain / Android: Keystore / Desktop: OSキーチェーンに保存する。
- `docs/03_技術仕様書.md` §5.3: SQLCipherの鍵は**常にDKからHKDFで導出**する（登録状態によらず一貫。MK由来には切り替えない）。
- `docs/03_技術仕様書.md` §7.1: 初回起動フロー = 1) DK生成しOSキーチェーンへ保存 → 2) DK由来の鍵でローカルDBを初期化・暗号化。

本タスクではOSキーチェーンの**プラットフォーム実装は行わず**、trait抽象とテストダブル（インメモリ実装）までを実装する。実プラットフォーム実装（iOS Keychain等）はブリッジ/アプリ統合の後続タスクで行う。

`core/crypto` にはtask-01のPoCにより `derive_key(ikm, info) -> [u8; 32]`（HKDF-SHA256）が、`core/storage` にはtask-02/task-06により `open_encrypted(path, key)` が実装済みである。本タスクはこの2つを、DK生成・保存という初回起動フローの起点でつなぐ。

## 2. 事前に読むべきファイル

- `docs/03_技術仕様書.md` §4.2/§4.3（鍵階層・DK定義）、§5.3（ローカルDB鍵）、§7.1（初回起動フロー）
- `core/crypto/src/kdf.rs`（既存 `derive_key(ikm, info) -> [u8; 32]`）
- `core/crypto/src/lib.rs`（re-exportスタイル）
- `core/storage/src/lib.rs`（`open_encrypted(path, key)`）
- `docs/07_Phase1計画書.md` M1-04

## 3. ゴール

`core/crypto` にDevice Key (DK) の生成・OSキーチェーン抽象（trait）・SQLCipher用ローカルDB鍵導出を実装し、`core/storage` の統合テストでDK生成からDB openまでの一気通貫動作を実証する。`cargo test --workspace` で緑になること。

## 4. スコープ

### やること

1. **`core/crypto/src/device_key.rs`（新規モジュール）**を作成する。
   - `pub const DEVICE_KEY_LEN: usize = 32;`
   - `pub fn generate_device_key() -> [u8; 32]` — `rand::rngs::OsRng`（既存依存）で32byte乱数を生成する。
   - `pub fn derive_local_db_key(device_key: &[u8; 32]) -> [u8; 32]` — 既存 `kdf::derive_key` を用い、infoにはバージョン付き文脈文字列 `b"todori/local-db-key/v1"` を使用する（§5.3のHKDF導出）。文脈文字列はコード内定数として定義し、ドキュメントコメントで意図を明記すること。
   - `pub trait DeviceKeyStore` — OSキーチェーン抽象。メソッドは `load(&self) -> Result<Option<[u8; 32]>, KeyStoreError>` / `store(&mut self, key: &[u8; 32]) -> Result<(), KeyStoreError>` / `delete(&mut self) -> Result<(), KeyStoreError>` の3つとする。エラー型 `KeyStoreError` は `thiserror` で定義し、プラットフォーム実装が返しうる失敗を表現できるよう `Backend(String)` のような汎用バリアントを含めること。
   - `pub fn ensure_device_key(store: &mut impl DeviceKeyStore) -> Result<[u8; 32], KeyStoreError>` — §7.1の初回起動フローを表す関数。`load` して存在すればそれを返し、無ければ `generate_device_key` → `store` → 返す。
   - `pub struct InMemoryDeviceKeyStore` — テストダブル兼デスクトップ開発用の暫定実装。`Option<[u8; 32]>` を保持するだけでよい。ドキュメントコメントに「本番のOSキーチェーン実装は後続タスク。平文でメモリ保持するため本番使用禁止」と明記すること。
2. **`core/crypto/src/lib.rs`**に `pub mod device_key;` を追加し、既存スタイルに倣ったre-exportを行う。
3. **`core/crypto` 内の単体テスト**を追加する。少なくとも以下を含めること。
   - 生成される鍵が32byteで、毎回異なること。
   - `derive_local_db_key` が決定的であり、入力DKが異なれば出力も異なること。
   - `ensure_device_key` が初回は生成・保存し、2回目は同じ鍵を返すこと。
   - `delete` 後の `ensure_device_key` は新しい鍵を生成すること。
4. **`core/storage` に統合テストを追加**する（M1-04完了条件「開発ホスト上のテストダブルでDK生成からDB openまでのテストが通ること」に対応）。
   - `core/storage/Cargo.toml` の `[dev-dependencies]` に `todori-crypto.workspace = true` を追加する（workspace path依存のためネットワーク不要）。
   - テスト内容: `InMemoryDeviceKeyStore` で `ensure_device_key` → `derive_local_db_key` → `open_encrypted` でDB作成・タスク書き込み → 接続を閉じ、**同じstoreから再度 `ensure_device_key` で得たDK**から導出した鍵で再オープンして読めること。加えて、**異なるDK**から導出した鍵では再オープンに失敗すること。
5. 秘密鍵素材（DK・導出鍵）を `Debug`/`Display`/ログに出さないこと。`InMemoryDeviceKeyStore` に `#[derive(Debug)]` を付ける場合は、鍵フィールドが出力されない工夫をすること（deriveしない、が最も簡単）。

### やらないこと

- iOS Keychain / Android Keystore / macOSキーチェーンの実プラットフォーム実装（後続タスクで行う）。
- `app/` およびFlutterブリッジ（`flutter_rust_bridge`）まわりの変更。
- MK/`wrap(MK, DK)` の実装（Phase 2、task-01のPoC参照）。
- テナント別DBファイル分離の実装（鍵は共通なので本タスクの導出関数はそのまま使える。`docs/03_技術仕様書.md` §5.1参照）。
- DKローテーション。
- 新規依存クレートの追加。`rand` / `hkdf` / `sha2` / `thiserror` / `todori-crypto` は既存依存を再利用すること。本タスクの実行環境はネットワークアクセス不可であるため、crates.ioからの新規取得が発生する変更を行ってはならない。
- zeroize等によるメモリ消去の強化。本タスクでは行わず、必要性を完了報告の未解決事項に記録すること。

## 5. 実装手順（例）

1. `core/crypto/src/kdf.rs` と `core/crypto/src/lib.rs` を再読し、既存のモジュール構成・re-exportスタイルを把握する。
2. `core/crypto/src/device_key.rs` を新規作成し、`DEVICE_KEY_LEN` / `generate_device_key` / `derive_local_db_key` / `DeviceKeyStore` / `KeyStoreError` / `ensure_device_key` / `InMemoryDeviceKeyStore` を実装する。
3. `core/crypto/src/lib.rs` に `pub mod device_key;` と re-export を追加する。
4. `device_key.rs` 内 `#[cfg(test)] mod tests` に単体テストを実装する。文脈文字列 `todori/local-db-key/v1` の値は、既知DK（例: `[0x42; 32]`）に対する導出結果を `[u8; 32]` のバイト配列リテラルとしてテストに埋め込み固定する（`core/crypto` に `hex` 依存は無く、新規依存追加は禁止のためhex文字列は使わない）。
5. `core/storage/Cargo.toml` の `[dev-dependencies]` に `todori-crypto.workspace = true` を追加する。
6. `core/storage/src/lib.rs` の既存 `#[cfg(test)] mod tests` に、DK生成からDB open・再オープンまでの統合テストを追記する。
7. `cargo test -p todori-crypto device_key::` および `cargo test -p todori-storage` を繰り返し実行しながら実装する。
8. 最後に `cargo fmt --all`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行し全体の品質ゲートを確認する。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する
- [ ] `cargo test --workspace` が全テスト成功する（既存の `core/crypto` / `core/storage` 等のテストも含めすべて成功すること）
- [ ] `cargo test -p todori-crypto device_key::` の新規テストがすべて成功する
- [ ] `cargo test -p todori-storage` でDK→DB openの統合テストが成功する（正鍵で読める・異なるDKでは失敗する、の両方を含む）

## 7. 制約・注意事項

- 既存 `aead` / `kdf` / `opaque` の公開APIを変更しないこと。
- 文脈文字列 `todori/local-db-key/v1` は将来の互換性に関わるため、テストで値そのものを固定すること（スナップショット的に、既知DKに対する導出結果を `[u8; 32]` バイト配列リテラルとしてテストに埋め込み、意図しない変更を検出できるようにする）。
- 秘密鍵素材（DK・導出鍵）を `Debug`/`Display`/ログに出さないこと。
- 仕様書（`docs/03_技術仕様書.md`）の記述だけでは一意に決まらない実装判断が生じた場合は、独断で仕様書側を変更せず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` / `docs/04_課金設計書.md` / `docs/07_Phase1計画書.md` は変更しないこと。

## 8. 完了報告に含めるべき内容

- 追加した公開API（trait・関数・型・エラー型）の一覧
- 文脈文字列（`todori/local-db-key/v1`）の値
- 追加したテストの総数（`core/crypto` / `core/storage` 別）
- zeroize等メモリ衛生に関する所見（本タスクで対応しなかった理由と、必要性の評価）
- 未解決事項（あれば）
