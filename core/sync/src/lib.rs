//! `todori-sync`: HLC・差分検出・push/pull同期エンジンを提供する crate。
//!
//! 詳細は `docs/03_技術仕様書.md` §6 同期プロトコル を参照。
//!
//! TODO: フィールドレベルLWWマージ、`sort_order` のfractional indexing、
//! `outbox` によるpush/pullフローは未実装（`docs/03_技術仕様書.md` §6.3, §6.4）。
//! 本crateは現時点ではHybrid Logical Clockの骨格のみを提供する。

pub mod hlc;

pub use hlc::Hlc;
