use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub const SYNC_PROTOCOL_VERSION: u16 = 4;
pub const SYNC_PROTOCOL_VERSION_HEADER: &str = "x-todori-protocol-version";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SyncCapabilities {
    pub protocol_version: u16,
    pub envelope_version: u8,
    pub gc_horizon_seq: i64,
    pub continuity_seq: i64,
    pub continuity_generation: i64,
    pub required_generation: i64,
    pub full_resync_required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResyncStartResponse {
    pub base_seq: i64,
    pub generation: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ClosureProof {
    pub proof_id: Uuid,
    pub tenant_id: Uuid,
    pub device_id: Uuid,
    pub high_water: i64,
    pub generation: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContinuityAckRequest {
    pub proof: ClosureProof,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContinuityAckResponse {
    pub continuity_seq: i64,
    pub continuity_generation: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyncCollection {
    Lists,
    Tasks,
}

impl SyncCollection {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Lists => "lists",
            Self::Tasks => "tasks",
        }
    }
}

impl fmt::Display for SyncCollection {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for SyncCollection {
    type Err = ProtocolTypeError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "lists" => Ok(Self::Lists),
            "tasks" => Ok(Self::Tasks),
            _ => Err(ProtocolTypeError::UnknownCollection(value.to_string())),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum SyncRecordState {
    Live { mutation_hlc: String, blob: String },
    Tombstone { delete_hlc: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SyncRecord {
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub seq: i64,
    pub revision_hlc: String,
    pub state: SyncRecordState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PushRequest {
    pub ops: Vec<PushOp>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PushOp {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub base_revision_hlc: Option<String>,
    pub revision_hlc: String,
    pub state: SyncRecordState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PushResponse {
    pub results: Vec<PushResult>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PushResult {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub status: PushStatus,
    pub seq: Option<i64>,
    pub current: Option<SyncRecord>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PushStatus {
    Accepted,
    NoOp,
    Superseded,
    Conflict,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PullResponse {
    pub records: Vec<SyncRecord>,
    pub next_since: i64,
    pub has_more: bool,
    pub high_water: i64,
    pub closure_proof: Option<ClosureProof>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StableRecordCursor {
    pub collection: SyncCollection,
    pub record_id: Uuid,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BaseScanResponse {
    pub records: Vec<SyncRecord>,
    pub next_cursor: Option<StableRecordCursor>,
    pub has_more: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ProtocolTypeError {
    #[error("unknown sync collection: {0}")]
    UnknownCollection(String),
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn record_state_is_strictly_tagged() {
        let live: SyncRecordState = serde_json::from_value(json!({
            "kind": "live",
            "mutation_hlc": "mutation",
            "blob": "ciphertext"
        }))
        .unwrap();
        assert_eq!(
            live,
            SyncRecordState::Live {
                mutation_hlc: "mutation".to_string(),
                blob: "ciphertext".to_string(),
            }
        );

        let tombstone: SyncRecordState = serde_json::from_value(json!({
            "kind": "tombstone",
            "delete_hlc": "delete"
        }))
        .unwrap();
        assert_eq!(
            tombstone,
            SyncRecordState::Tombstone {
                delete_hlc: "delete".to_string(),
            }
        );

        assert!(serde_json::from_value::<SyncRecordState>(json!({
            "kind": "tombstone",
            "delete_hlc": "delete",
            "blob": "must-not-exist"
        }))
        .is_err());
        assert!(serde_json::from_value::<SyncRecordState>(json!({
            "kind": "live",
            "mutation_hlc": "mutation"
        }))
        .is_err());
    }

    #[test]
    fn collection_rejects_unknown_values() {
        assert_eq!("tasks".parse(), Ok(SyncCollection::Tasks));
        assert!("reminders".parse::<SyncCollection>().is_err());
        assert!(serde_json::from_value::<SyncCollection>(json!("Tasks")).is_err());
    }
}
