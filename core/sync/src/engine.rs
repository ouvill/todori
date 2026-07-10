//! HTTP sync engine client for the strict protocol v2 wire contract.

use std::collections::{HashMap, HashSet};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::StatusCode;
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::{
    protocol::{
        self, PullResponse, PushRequest, SyncCollection, SyncRecordState as WireRecordState,
    },
    Hlc,
};

pub use crate::protocol::PushStatus;

#[derive(Debug, Error)]
pub enum SyncEngineError {
    #[error("server URL is empty")]
    EmptyServerUrl,
    #[error("HTTP request failed")]
    Http(#[from] reqwest::Error),
    #[error("server rejected sync request: {0}")]
    Server(StatusCode),
    #[error("invalid sync request")]
    InvalidRequest,
    #[error("invalid push response")]
    InvalidPushResponse,
    #[error("invalid pull response")]
    InvalidPullResponse,
    #[error("sync client upgrade required")]
    UpgradeRequired {
        protocol_version: u16,
        envelope_version: u8,
    },
}

#[derive(Debug, Clone)]
pub struct SyncEngine {
    base_url: String,
    tenant_id: Uuid,
    session_token: Zeroizing<String>,
    http: reqwest::Client,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EncryptedSyncState {
    Live { mutation_hlc: String, blob: Vec<u8> },
    Tombstone { delete_hlc: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushOp {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub base_revision_hlc: Option<String>,
    pub revision_hlc: String,
    pub state: EncryptedSyncState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushBatchOutcome {
    pub outcomes: Vec<PushOpOutcome>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushOpOutcome {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub status: PushStatus,
    pub seq: Option<i64>,
    pub current: Option<PullRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PullPage {
    pub records: Vec<PullRecord>,
    pub next_since: i64,
    pub has_more: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PullRecord {
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub seq: i64,
    pub revision_hlc: String,
    pub state: EncryptedSyncState,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SyncRunSummary {
    pub pushed_count: usize,
    pub push_acked_count: usize,
    pub push_superseded_count: usize,
    pub push_conflict_count: usize,
    pub pulled_count: usize,
    pub applied_count: usize,
    pub deleted_count: usize,
    pub decrypt_failed_count: usize,
    pub repush_count: usize,
    pub missing_key_quarantined_count: usize,
    pub corruption_quarantined_count: usize,
    pub resolved_quarantine_count: usize,
}

impl SyncEngine {
    pub fn new(
        server_url: impl Into<String>,
        tenant_id: Uuid,
        session_token: impl Into<String>,
    ) -> Result<Self, SyncEngineError> {
        let base_url = normalize_base_url(server_url.into())?;
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()?;
        Ok(Self {
            base_url,
            tenant_id,
            session_token: Zeroizing::new(session_token.into()),
            http,
        })
    }

    pub async fn preflight(&self) -> Result<(), SyncEngineError> {
        let response = self
            .http
            .get(format!(
                "{}/v2/tenants/{}/preflight",
                self.base_url, self.tenant_id
            ))
            .bearer_auth(self.session_token.as_str())
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(SyncEngineError::Server(response.status()));
        }
        let capabilities = response.json::<protocol::SyncCapabilities>().await?;
        if capabilities.protocol_version != protocol::SYNC_PROTOCOL_VERSION
            || capabilities.envelope_version != crate::ENVELOPE_VERSION
        {
            return Err(SyncEngineError::UpgradeRequired {
                protocol_version: capabilities.protocol_version,
                envelope_version: capabilities.envelope_version,
            });
        }
        Ok(())
    }

    pub async fn push_batch(&self, ops: Vec<PushOp>) -> Result<PushBatchOutcome, SyncEngineError> {
        if ops.is_empty() {
            return Ok(PushBatchOutcome {
                outcomes: Vec::new(),
            });
        }
        validate_push_ops(&ops)?;
        let request = PushRequest {
            ops: ops.iter().map(to_wire_push_op).collect(),
        };
        let response = self
            .http
            .post(format!(
                "{}/v2/tenants/{}/push",
                self.base_url, self.tenant_id
            ))
            .bearer_auth(self.session_token.as_str())
            .json(&request)
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(SyncEngineError::Server(response.status()));
        }
        let response = response.json::<protocol::PushResponse>().await?;
        validate_push_response(&ops, response)
    }

    pub async fn pull_page(&self, since: i64, limit: i64) -> Result<PullPage, SyncEngineError> {
        let response = self
            .http
            .get(format!(
                "{}/v2/tenants/{}/pull",
                self.base_url, self.tenant_id
            ))
            .bearer_auth(self.session_token.as_str())
            .query(&[("since", since), ("limit", limit)])
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(SyncEngineError::Server(response.status()));
        }
        let response = response.json::<PullResponse>().await?;
        validate_pull_response(since, response)
    }
}

fn normalize_base_url(mut value: String) -> Result<String, SyncEngineError> {
    value = value.trim().trim_end_matches('/').to_string();
    if value.is_empty() {
        return Err(SyncEngineError::EmptyServerUrl);
    }
    Ok(value)
}

fn validate_push_ops(ops: &[PushOp]) -> Result<(), SyncEngineError> {
    let mut op_ids = HashSet::with_capacity(ops.len());
    for op in ops {
        if !op_ids.insert(op.op_id)
            || Hlc::decode(&op.revision_hlc).is_err()
            || op
                .base_revision_hlc
                .as_deref()
                .is_some_and(|base| Hlc::decode(base).is_err())
            || !valid_state_for_revision(&op.revision_hlc, &op.state)
        {
            return Err(SyncEngineError::InvalidRequest);
        }
    }
    Ok(())
}

fn valid_state_for_revision(revision_hlc: &str, state: &EncryptedSyncState) -> bool {
    let Ok(revision) = Hlc::decode(revision_hlc) else {
        return false;
    };
    let (semantic_hlc, shape_is_valid) = match state {
        EncryptedSyncState::Live { mutation_hlc, blob } => (mutation_hlc, !blob.is_empty()),
        EncryptedSyncState::Tombstone { delete_hlc } => (delete_hlc, true),
    };
    shape_is_valid && Hlc::decode(semantic_hlc).is_ok_and(|semantic| revision >= semantic)
}

fn to_wire_push_op(op: &PushOp) -> protocol::PushOp {
    protocol::PushOp {
        op_id: op.op_id,
        record_id: op.record_id,
        collection: op.collection,
        base_revision_hlc: op.base_revision_hlc.clone(),
        revision_hlc: op.revision_hlc.clone(),
        state: to_wire_state(&op.state),
    }
}

fn to_wire_state(state: &EncryptedSyncState) -> WireRecordState {
    match state {
        EncryptedSyncState::Live { mutation_hlc, blob } => WireRecordState::Live {
            mutation_hlc: mutation_hlc.clone(),
            blob: STANDARD.encode(blob),
        },
        EncryptedSyncState::Tombstone { delete_hlc } => WireRecordState::Tombstone {
            delete_hlc: delete_hlc.clone(),
        },
    }
}

fn validate_push_response(
    ops: &[PushOp],
    response: protocol::PushResponse,
) -> Result<PushBatchOutcome, SyncEngineError> {
    if response.results.len() != ops.len() {
        return Err(SyncEngineError::InvalidPushResponse);
    }
    let expected = ops
        .iter()
        .map(|op| (op.op_id, (op.record_id, op.collection)))
        .collect::<HashMap<_, _>>();
    let mut decoded = HashMap::with_capacity(response.results.len());
    for result in response.results {
        let Some((record_id, collection)) = expected.get(&result.op_id).copied() else {
            return Err(SyncEngineError::InvalidPushResponse);
        };
        if result.record_id != record_id
            || result.collection != collection
            || decoded.contains_key(&result.op_id)
        {
            return Err(SyncEngineError::InvalidPushResponse);
        }
        let current = result
            .current
            .map(decode_record)
            .transpose()
            .map_err(|_| SyncEngineError::InvalidPushResponse)?;
        if current.as_ref().is_some_and(|current| {
            current.record_id != record_id
                || current.collection != collection
                || result.seq.is_some_and(|seq| seq != current.seq)
        }) {
            return Err(SyncEngineError::InvalidPushResponse);
        }
        let valid_shape = match result.status {
            PushStatus::Accepted | PushStatus::NoOp => result.seq.is_some() && current.is_none(),
            PushStatus::Superseded => result.seq.is_some() && current.is_some(),
            PushStatus::Conflict => matches!(
                (result.seq, current.as_ref()),
                (Some(_), Some(_)) | (None, None)
            ),
        };
        if !valid_shape {
            return Err(SyncEngineError::InvalidPushResponse);
        }
        decoded.insert(
            result.op_id,
            PushOpOutcome {
                op_id: result.op_id,
                record_id,
                collection,
                status: result.status,
                seq: result.seq,
                current,
            },
        );
    }
    let outcomes = ops
        .iter()
        .map(|op| {
            decoded
                .remove(&op.op_id)
                .ok_or(SyncEngineError::InvalidPushResponse)
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(PushBatchOutcome { outcomes })
}

fn validate_pull_response(since: i64, response: PullResponse) -> Result<PullPage, SyncEngineError> {
    if response.next_since < since {
        return Err(SyncEngineError::InvalidPullResponse);
    }
    let mut previous_seq = since;
    let mut records = Vec::with_capacity(response.records.len());
    for record in response.records {
        let record = decode_record(record)?;
        if record.seq <= previous_seq || record.seq > response.next_since {
            return Err(SyncEngineError::InvalidPullResponse);
        }
        previous_seq = record.seq;
        records.push(record);
    }
    if records
        .last()
        .is_some_and(|record| record.seq != response.next_since)
    {
        return Err(SyncEngineError::InvalidPullResponse);
    }
    Ok(PullPage {
        records,
        next_since: response.next_since,
        has_more: response.has_more,
    })
}

fn decode_record(record: protocol::SyncRecord) -> Result<PullRecord, SyncEngineError> {
    if record.seq <= 0 || Hlc::decode(&record.revision_hlc).is_err() {
        return Err(SyncEngineError::InvalidPullResponse);
    }
    let state = match record.state {
        WireRecordState::Live { mutation_hlc, blob } => {
            let blob = STANDARD
                .decode(blob)
                .map_err(|_| SyncEngineError::InvalidPullResponse)?;
            let state = EncryptedSyncState::Live { mutation_hlc, blob };
            if !valid_state_for_revision(&record.revision_hlc, &state) {
                return Err(SyncEngineError::InvalidPullResponse);
            }
            state
        }
        WireRecordState::Tombstone { delete_hlc } => {
            let state = EncryptedSyncState::Tombstone { delete_hlc };
            if !valid_state_for_revision(&record.revision_hlc, &state) {
                return Err(SyncEngineError::InvalidPullResponse);
            }
            state
        }
    };
    Ok(PullRecord {
        record_id: record.record_id,
        collection: record.collection,
        seq: record.seq,
        revision_hlc: record.revision_hlc,
        state,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clock(device: &str, counter: u32) -> String {
        Hlc {
            wall_ms: 1_799_000_000_000,
            counter,
            device_id: device.to_string(),
        }
        .encode()
        .unwrap()
    }

    fn push_op(op_id: Uuid, record_id: Uuid) -> PushOp {
        PushOp {
            op_id,
            record_id,
            collection: SyncCollection::Tasks,
            base_revision_hlc: None,
            revision_hlc: clock("local", 1),
            state: EncryptedSyncState::Live {
                mutation_hlc: clock("local", 1),
                blob: vec![1, 2, 3],
            },
        }
    }

    fn accepted(op: &PushOp) -> protocol::PushResult {
        protocol::PushResult {
            op_id: op.op_id,
            record_id: op.record_id,
            collection: op.collection,
            status: PushStatus::Accepted,
            seq: Some(1),
            current: None,
        }
    }

    #[test]
    fn rejects_empty_server_url() {
        let error = SyncEngine::new(" ", Uuid::now_v7(), "token").unwrap_err();
        assert!(matches!(error, SyncEngineError::EmptyServerUrl));
    }

    #[test]
    fn push_response_can_be_reordered_and_is_returned_in_request_order() {
        let first = push_op(Uuid::now_v7(), Uuid::now_v7());
        let second = push_op(Uuid::now_v7(), Uuid::now_v7());
        let response = protocol::PushResponse {
            results: vec![accepted(&second), accepted(&first)],
        };

        let outcome = validate_push_response(&[first.clone(), second.clone()], response).unwrap();

        assert_eq!(outcome.outcomes[0].op_id, first.op_id);
        assert_eq!(outcome.outcomes[1].op_id, second.op_id);
    }

    #[test]
    fn push_response_rejects_missing_duplicate_unknown_and_record_mismatch() {
        let first = push_op(Uuid::now_v7(), Uuid::now_v7());
        let second = push_op(Uuid::now_v7(), Uuid::now_v7());
        let cases = [
            protocol::PushResponse {
                results: vec![accepted(&first)],
            },
            protocol::PushResponse {
                results: vec![accepted(&first), accepted(&first)],
            },
            protocol::PushResponse {
                results: vec![
                    accepted(&first),
                    accepted(&push_op(Uuid::now_v7(), second.record_id)),
                ],
            },
            protocol::PushResponse {
                results: vec![
                    accepted(&first),
                    protocol::PushResult {
                        record_id: Uuid::now_v7(),
                        ..accepted(&second)
                    },
                ],
            },
        ];

        for response in cases {
            assert!(matches!(
                validate_push_response(&[first.clone(), second.clone()], response),
                Err(SyncEngineError::InvalidPushResponse)
            ));
        }
    }

    #[test]
    fn push_response_rejects_invalid_status_shapes() {
        let op = push_op(Uuid::now_v7(), Uuid::now_v7());
        let current = protocol::SyncRecord {
            record_id: op.record_id,
            collection: op.collection,
            seq: 1,
            revision_hlc: clock("remote", 2),
            state: WireRecordState::Live {
                mutation_hlc: clock("remote", 1),
                blob: STANDARD.encode([1, 2, 3]),
            },
        };
        let invalid = [
            protocol::PushResponse {
                results: vec![protocol::PushResult {
                    op_id: op.op_id,
                    record_id: op.record_id,
                    collection: op.collection,
                    status: PushStatus::Superseded,
                    seq: None,
                    current: Some(current.clone()),
                }],
            },
            protocol::PushResponse {
                results: vec![protocol::PushResult {
                    op_id: op.op_id,
                    record_id: op.record_id,
                    collection: op.collection,
                    status: PushStatus::Conflict,
                    seq: Some(1),
                    current: None,
                }],
            },
        ];

        for response in invalid {
            assert!(matches!(
                validate_push_response(std::slice::from_ref(&op), response),
                Err(SyncEngineError::InvalidPushResponse)
            ));
        }
    }

    #[test]
    fn pull_rejects_invalid_base64_and_clock() {
        let response = PullResponse {
            records: vec![protocol::SyncRecord {
                record_id: Uuid::now_v7(),
                collection: SyncCollection::Tasks,
                seq: 1,
                revision_hlc: clock("remote", 1),
                state: WireRecordState::Live {
                    mutation_hlc: clock("remote", 1),
                    blob: "%%%".to_string(),
                },
            }],
            next_since: 1,
            has_more: false,
        };
        assert!(matches!(
            validate_pull_response(0, response),
            Err(SyncEngineError::InvalidPullResponse)
        ));

        let response = PullResponse {
            records: vec![protocol::SyncRecord {
                record_id: Uuid::now_v7(),
                collection: SyncCollection::Tasks,
                seq: 1,
                revision_hlc: "invalid".to_string(),
                state: WireRecordState::Tombstone {
                    delete_hlc: clock("remote", 1),
                },
            }],
            next_since: 1,
            has_more: false,
        };
        assert!(matches!(
            validate_pull_response(0, response),
            Err(SyncEngineError::InvalidPullResponse)
        ));

        let response = PullResponse {
            records: vec![protocol::SyncRecord {
                record_id: Uuid::now_v7(),
                collection: SyncCollection::Tasks,
                seq: 1,
                revision_hlc: clock("remote", 1),
                state: WireRecordState::Tombstone {
                    delete_hlc: clock("remote", 2),
                },
            }],
            next_since: 1,
            has_more: false,
        };
        assert!(matches!(
            validate_pull_response(0, response),
            Err(SyncEngineError::InvalidPullResponse)
        ));
    }
}
