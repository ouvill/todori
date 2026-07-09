//! Frontend-independent Todori client application services.
//!
//! This crate is the shared entry point for Flutter, CLI, and MCP. It owns
//! transaction boundaries that span domain rows and local sync bookkeeping.

mod task_service;

pub use task_service::{Client, ClientError, LocalMutationContext, UpdateTaskInput};
