//! ルーティングのモジュール構成。
//!
//! ディレクトリ構成は `docs/03_技術仕様書.md` §2 の `server/` 配下
//! (`auth/` `tenant/` `sync-token/` `billing/`) に対応する
//! （Rustのモジュール命名規則上 `sync-token` は `sync_token` とする）。
//! 各モジュールの実装は後続タスクで行う。

pub mod auth;
pub mod billing;
pub mod sync_token;
pub mod tenant;
