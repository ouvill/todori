//! Frontend-independent Todori client application services.
//!
//! This crate is the shared entry point for Flutter, CLI, and MCP. It owns
//! transaction boundaries that span domain rows and local sync bookkeeping.
//!
//! Frontends must enter through [`ClientProfile`]. Low-level storage and sync
//! orchestration types are deliberately not part of the normal public API:
//!
//! ```compile_fail
//! use todori_client::Client;
//! ```
//!
//! ```compile_fail
//! use todori_client::SqliteSyncStore;
//! ```

mod crud_service;
mod local_crypto;
mod model;
mod profile;
mod sqlite_sync_store;
mod task_service;

pub(crate) use crud_service::{CreateTaskInput, ReorderTaskInput, SetTaskStatusInput};
pub(crate) use local_crypto::{
    load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
    LocalCryptoAvailability, LocalCryptoContext, LocalCryptoIdentity, LocalCryptoUnavailable,
};
pub use model::{AccountAuthResult, AccountSessionState, SyncStatus};
pub use profile::{
    ClientProfile, CreateTaskCommand, HomeTaskView, ProfileConfig, ReminderView,
    ReorderTaskCommand, SetTaskStatusCommand, TaskUndoKind, TaskUndoView, UpdateTaskCommand,
};
pub(crate) use sqlite_sync_store::SqliteSyncStore;
pub use task_service::ClientError;
pub(crate) use task_service::{Client, LocalMutationContext, UpdateTaskInput};
pub use todori_domain::{List, Task, TaskStatus, Uuid};

/// Unstable low-level primitives for cross-crate integration tests.
///
/// Product frontends must not enable this feature. These exports may change as
/// the internal client implementation evolves; [`ClientProfile`] is the only
/// supported application entry point.
#[cfg(feature = "test-support")]
pub mod test_support {
    pub use crate::crud_service::{CreateTaskInput, ReorderTaskInput, SetTaskStatusInput};
    pub use crate::local_crypto::{
        load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
        LocalCryptoAvailability, LocalCryptoContext, LocalCryptoIdentity, LocalCryptoUnavailable,
    };
    pub use crate::sqlite_sync_store::{SqliteSyncStore, SqliteSyncWriteTx};
    pub use crate::task_service::{Client, LocalMutationContext, UpdateTaskInput};
}
