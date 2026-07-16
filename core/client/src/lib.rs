//! Frontend-independent Todori client application services.
//!
//! This crate is the shared entry point for Flutter, CLI, and MCP. It owns
//! transaction boundaries that span domain rows and local sync bookkeeping.
//!
//! Frontends must enter through [`TodoriClient`]. Low-level storage and sync
//! orchestration types are deliberately not part of the normal public API:
//!
//! ```no_run
//! use todori_client::{LocalProfileConfig, TodoriClient};
//!
//! let client = TodoriClient::open(LocalProfileConfig::new("/tmp/todori", "Inbox"))?;
//! # Ok::<(), todori_client::ClientError>(())
//! ```
//!
//! The superseded pre-release names are intentionally unavailable:
//!
//! ```compile_fail
//! use todori_client::{ClientProfile, ProfileConfig};
//! ```
//!
//! ```compile_fail
//! use todori_client::SqliteMutationService;
//! ```
//!
//! ```compile_fail
//! use todori_client::SqliteSyncStore;
//! ```

mod crud_service;
mod device_key_rotation;
mod local_crypto;
mod model;
mod mutation_service;
mod runtime;
mod sqlite_sync_store;

pub(crate) use crud_service::{CreateTaskInput, ReorderTaskInput, SetTaskStatusInput};
pub(crate) use local_crypto::{
    load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
    LocalCryptoAvailability, LocalCryptoContext, LocalCryptoIdentity, LocalCryptoUnavailable,
};
pub use model::{
    AccountAuthResult, AccountSessionState, BillingState, OrganizationSafetyState, RealtimeTicket,
    SyncStatus,
};
pub use mutation_service::ClientError;
pub(crate) use mutation_service::{LocalMutationContext, SqliteMutationService, UpdateTaskInput};
pub use runtime::{
    CalendarOccurrenceKind, CalendarOccurrenceView, CalendarRange, CreateTaskCommand, HomeTaskView,
    LocalProfileConfig, ReminderView, ReorderTaskCommand, SetTaskStatusCommand, TaskUndoKind,
    TaskUndoView, TodoriClient, UpdateTaskCommand,
};
pub(crate) use sqlite_sync_store::SqliteSyncStore;
pub use todori_domain::{
    pomodoro_target_reached_at, ActiveTimerSession, CivilDate, CompletedTimerSession,
    DueValueError, IanaTimeZone, List, Task, TaskDue, TaskStatus, TimerFinishKind, TimerMode,
    TimerPhase, TimerRunState, UtcInstant, Uuid,
};

pub use chrono;

/// Unstable low-level primitives for cross-crate integration tests.
///
/// Product frontends must not enable this feature. These exports may change as
/// the internal client implementation evolves; [`TodoriClient`] is the only
/// supported application entry point.
#[cfg(feature = "test-support")]
pub mod test_support {
    pub use crate::crud_service::{CreateTaskInput, ReorderTaskInput, SetTaskStatusInput};
    pub use crate::local_crypto::{
        load_local_crypto_context, persist_account_crypto_context, persist_local_crypto_context,
        LocalCryptoAvailability, LocalCryptoContext, LocalCryptoIdentity, LocalCryptoUnavailable,
    };
    pub use crate::mutation_service::{
        LocalMutationContext, SqliteMutationService, UpdateTaskInput,
    };
    pub use crate::sqlite_sync_store::{SqliteSyncStore, SqliteSyncWriteTx};
}
