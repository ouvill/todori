//! `todori-storage`: ローカルストレージアクセス層。
//!
//! TODO: SQLite(SQLCipher) の統合（`rusqlite` の bundled-sqlcipher 系feature）は
//! ビルド検証タスクで実施予定（`docs/03_技術仕様書.md` §5.1, §12）。
//! 本crateは現時点では `TaskRepository` トレイトのスタブのみを提供する。

use thiserror::Error;
use todori_domain::{Task, Uuid};

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("task not found: {0}")]
    NotFound(Uuid),
    #[error("storage backend not implemented yet")]
    NotImplemented,
}

/// タスクの永続化を担うリポジトリ。
///
/// 現時点ではSQLCipher統合前のスタブであり、同期シグネチャのみを定義する。
pub trait TaskRepository {
    fn get(&self, id: Uuid) -> Result<Task, StorageError>;
    fn insert(&mut self, task: Task) -> Result<(), StorageError>;
    fn update(&mut self, task: Task) -> Result<(), StorageError>;
}
