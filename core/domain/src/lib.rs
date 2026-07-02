//! `todori-domain`: エンティティ・ユースケース（純粋ロジック）を提供する crate。
//!
//! 詳細な論理スキーマは `docs/03_技術仕様書.md` §3 データモデル を参照。

pub mod entities;

pub use entities::{List, Task, TaskStatus};
pub use uuid::Uuid;
