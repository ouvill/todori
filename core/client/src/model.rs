//! Frontend-neutral account and synchronization views.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountSessionState {
    pub logged_in: bool,
    pub email: Option<String>,
    pub user_id: Option<String>,
    pub tenant_id: Option<String>,
    pub device_id: Option<String>,
}

impl AccountSessionState {
    pub fn logged_out() -> Self {
        Self {
            logged_in: false,
            email: None,
            user_id: None,
            tenant_id: None,
            device_id: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountAuthResult {
    pub session: AccountSessionState,
    /// Intentionally exported once after registration so the user can store it.
    pub recovery_key: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SyncStatus {
    pub logged_in: bool,
    pub running: bool,
    pub last_success_at: Option<i64>,
    pub last_failure_at: Option<i64>,
    pub last_error: Option<String>,
    pub pushed_count: usize,
    pub push_acked_count: usize,
    pub push_superseded_count: usize,
    pub pulled_count: usize,
    pub applied_count: usize,
    pub deleted_count: usize,
    pub decrypt_failed_count: usize,
    pub repush_count: usize,
    pub missing_key_quarantined_count: usize,
    pub corruption_quarantined_count: usize,
    pub resolved_quarantine_count: usize,
    pub upgrade_required: bool,
}
