//! Frontend-independent Todori client application services.
//!
//! This crate is the shared entry point for Flutter, CLI, and MCP. It owns
//! transaction boundaries that span domain rows and local sync bookkeeping.

mod local_crypto;
mod task_service;

pub use local_crypto::{
    load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
    LocalCryptoAvailability, LocalCryptoContext, LocalCryptoIdentity, LocalCryptoUnavailable,
};
pub use task_service::{Client, ClientError, LocalMutationContext, UpdateTaskInput};
