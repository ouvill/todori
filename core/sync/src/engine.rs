//! HTTP sync engine client.
//!
//! The storage layer owns the SQLCipher DB and outbox tables. This module owns
//! the wire protocol for push/pull and returns enough metadata for callers to
//! ACK outbox rows, advance cursors after local commits, and count skipped
//! records without exposing account secrets.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroizing;

#[derive(Debug, Error)]
pub enum SyncEngineError {
    #[error("server URL is empty")]
    EmptyServerUrl,
    #[error("HTTP request failed")]
    Http(#[from] reqwest::Error),
    #[error("server rejected sync request: {0}")]
    Server(StatusCode),
}

#[derive(Debug, Clone)]
pub struct SyncEngine {
    base_url: String,
    tenant_id: Uuid,
    session_token: Zeroizing<String>,
    http: reqwest::Client,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushOp {
    pub outbox_id: i64,
    pub record_id: Uuid,
    pub collection: String,
    pub hlc: String,
    pub deleted: bool,
    pub blob: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushBatchOutcome {
    pub outcomes: Vec<PushOpOutcome>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushOpOutcome {
    pub outbox_id: i64,
    pub record_id: Uuid,
    pub status: PushStatus,
    pub seq: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PushStatus {
    Accepted,
    Superseded,
    NoOp,
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
    pub collection: String,
    pub seq: i64,
    pub hlc: String,
    pub deleted: bool,
    pub blob: Vec<u8>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SyncRunSummary {
    pub pushed_count: usize,
    pub push_acked_count: usize,
    pub push_superseded_count: usize,
    pub pulled_count: usize,
    pub applied_count: usize,
    pub deleted_count: usize,
    pub decrypt_failed_count: usize,
    pub repush_count: usize,
}

impl SyncEngine {
    pub fn new(
        server_url: impl Into<String>,
        tenant_id: Uuid,
        session_token: impl Into<String>,
    ) -> Result<Self, SyncEngineError> {
        let base_url = normalize_base_url(server_url.into())?;
        Ok(Self {
            base_url,
            tenant_id,
            session_token: Zeroizing::new(session_token.into()),
            http: reqwest::Client::new(),
        })
    }

    pub async fn push_batch(&self, ops: Vec<PushOp>) -> Result<PushBatchOutcome, SyncEngineError> {
        if ops.is_empty() {
            return Ok(PushBatchOutcome {
                outcomes: Vec::new(),
            });
        }
        let outbox_ids = ops.iter().map(|op| op.outbox_id).collect::<Vec<_>>();
        let request = PushRequest {
            ops: ops.into_iter().map(PushOpRequest::from).collect(),
        };
        let response = self
            .http
            .post(format!(
                "{}/v1/tenants/{}/push",
                self.base_url, self.tenant_id
            ))
            .bearer_auth(self.session_token.as_str())
            .json(&request)
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(SyncEngineError::Server(response.status()));
        }
        let response = response.json::<PushResponse>().await?;
        let outcomes = response
            .results
            .into_iter()
            .zip(outbox_ids)
            .map(|(result, outbox_id)| PushOpOutcome {
                outbox_id,
                record_id: result.record_id,
                status: result.status,
                seq: result.seq,
            })
            .collect();
        Ok(PushBatchOutcome { outcomes })
    }

    pub async fn pull_page(&self, since: i64, limit: i64) -> Result<PullPage, SyncEngineError> {
        let response = self
            .http
            .get(format!(
                "{}/v1/tenants/{}/pull",
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
        let mut records = Vec::with_capacity(response.records.len());
        for record in response.records {
            records.push(PullRecord {
                record_id: record.record_id,
                collection: record.collection,
                seq: record.seq,
                hlc: record.hlc,
                deleted: record.deleted,
                blob: STANDARD.decode(record.blob).unwrap_or_default(),
            });
        }
        Ok(PullPage {
            records,
            next_since: response.next_since,
            has_more: response.has_more,
        })
    }
}

fn normalize_base_url(mut value: String) -> Result<String, SyncEngineError> {
    value = value.trim().trim_end_matches('/').to_string();
    if value.is_empty() {
        return Err(SyncEngineError::EmptyServerUrl);
    }
    Ok(value)
}

#[derive(Debug, Serialize)]
struct PushRequest {
    ops: Vec<PushOpRequest>,
}

#[derive(Debug, Serialize)]
struct PushOpRequest {
    record_id: Uuid,
    collection: String,
    hlc: String,
    deleted: bool,
    blob: String,
}

impl From<PushOp> for PushOpRequest {
    fn from(op: PushOp) -> Self {
        Self {
            record_id: op.record_id,
            collection: op.collection,
            hlc: op.hlc,
            deleted: op.deleted,
            blob: STANDARD.encode(op.blob),
        }
    }
}

#[derive(Debug, Deserialize)]
struct PushResponse {
    results: Vec<PushOpResult>,
}

#[derive(Debug, Deserialize)]
struct PushOpResult {
    record_id: Uuid,
    status: PushStatus,
    seq: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct PullResponse {
    records: Vec<PullRecordResponse>,
    next_since: i64,
    has_more: bool,
}

#[derive(Debug, Deserialize)]
struct PullRecordResponse {
    record_id: Uuid,
    collection: String,
    seq: i64,
    hlc: String,
    deleted: bool,
    blob: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_server_url() {
        let error = SyncEngine::new(" ", Uuid::now_v7(), "token").unwrap_err();
        assert!(matches!(error, SyncEngineError::EmptyServerUrl));
    }

    #[test]
    fn push_op_encodes_blob_as_base64() {
        let op = PushOp {
            outbox_id: 7,
            record_id: Uuid::now_v7(),
            collection: "tasks".to_string(),
            hlc: "hlc".to_string(),
            deleted: false,
            blob: vec![1, 2, 3],
        };
        let dto = PushOpRequest::from(op);
        assert_eq!(dto.blob, "AQID");
    }
}
