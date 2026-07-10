//! Frontend-independent Todori client application services.
//!
//! This crate is the shared entry point for Flutter, CLI, and MCP. It owns
//! transaction boundaries that span domain rows and local sync bookkeeping.

mod crud_service;
mod local_crypto;
mod sqlite_sync_store;
mod task_service;

pub use crud_service::{CreateTaskInput, ReorderTaskInput, SetTaskStatusInput};
pub use local_crypto::{
    load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
    LocalCryptoAvailability, LocalCryptoContext, LocalCryptoIdentity, LocalCryptoUnavailable,
};
pub use sqlite_sync_store::{SqliteSyncStore, SqliteSyncWriteTx};
pub use task_service::{Client, ClientError, LocalMutationContext, UpdateTaskInput};
