//! Field-level Last-Write-Wins merge.

use std::collections::{BTreeMap, BTreeSet};

use serde_json::Value;

use crate::field_map::{FieldMapError, SyncPlaintext};
use crate::hlc::Hlc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergeResult {
    pub plaintext: SyncPlaintext,
    pub local_won_fields: BTreeSet<String>,
    pub incoming_won_fields: BTreeSet<String>,
}

impl MergeResult {
    pub fn needs_repush(&self) -> bool {
        !self.local_won_fields.is_empty()
    }
}

/// Merges two decrypted sync payloads with field-level LWW.
pub fn merge_lww(
    local: &SyncPlaintext,
    incoming: &SyncPlaintext,
) -> Result<MergeResult, FieldMapError> {
    local.validate()?;
    incoming.validate()?;

    let keys = local
        .fields
        .keys()
        .chain(incoming.fields.keys())
        .cloned()
        .collect::<BTreeSet<_>>();
    let mut fields = BTreeMap::new();
    let mut field_hlcs = BTreeMap::new();
    let mut local_won_fields = BTreeSet::new();
    let mut incoming_won_fields = BTreeSet::new();

    for key in keys {
        let local_value = local.fields.get(&key);
        let local_hlc = local.field_hlcs.get(&key);
        let incoming_value = incoming.fields.get(&key);
        let incoming_hlc = incoming.field_hlcs.get(&key);

        let winner = choose_winner(local_value, local_hlc, incoming_value, incoming_hlc);
        match winner {
            FieldWinner::Local { value, hlc } => {
                fields.insert(key.clone(), value.clone());
                field_hlcs.insert(key.clone(), hlc.clone());
                if incoming_value.is_none() || incoming_hlc.is_some_and(|incoming| hlc > incoming) {
                    local_won_fields.insert(key);
                }
            }
            FieldWinner::Incoming { value, hlc } => {
                fields.insert(key.clone(), value.clone());
                field_hlcs.insert(key.clone(), hlc.clone());
                if local_value.is_none() || local_hlc.is_some_and(|local| hlc > local) {
                    incoming_won_fields.insert(key);
                }
            }
        }
    }

    Ok(MergeResult {
        plaintext: SyncPlaintext::new(fields, field_hlcs)?,
        local_won_fields,
        incoming_won_fields,
    })
}

enum FieldWinner<'a> {
    Local { value: &'a Value, hlc: &'a Hlc },
    Incoming { value: &'a Value, hlc: &'a Hlc },
}

fn choose_winner<'a>(
    local_value: Option<&'a Value>,
    local_hlc: Option<&'a Hlc>,
    incoming_value: Option<&'a Value>,
    incoming_hlc: Option<&'a Hlc>,
) -> FieldWinner<'a> {
    match (local_value, local_hlc, incoming_value, incoming_hlc) {
        (Some(local_value), Some(local_hlc), Some(incoming_value), Some(incoming_hlc)) => {
            if local_hlc > incoming_hlc
                || (local_hlc == incoming_hlc
                    && canonical_value(local_value) >= canonical_value(incoming_value))
            {
                FieldWinner::Local {
                    value: local_value,
                    hlc: local_hlc,
                }
            } else {
                FieldWinner::Incoming {
                    value: incoming_value,
                    hlc: incoming_hlc,
                }
            }
        }
        (Some(value), Some(hlc), None, None) => FieldWinner::Local { value, hlc },
        (None, None, Some(value), Some(hlc)) => FieldWinner::Incoming { value, hlc },
        _ => unreachable!("SyncPlaintext::validate guarantees matching field/HLC keys"),
    }
}

fn canonical_value(value: &Value) -> String {
    serde_json::to_string(value).expect("serde_json::Value serializes")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn hlc(counter: u32, device_id: &str) -> Hlc {
        Hlc {
            wall_ms: 1_000,
            counter,
            device_id: device_id.to_string(),
        }
    }

    fn plaintext(entries: Vec<(&str, Value, Hlc)>) -> SyncPlaintext {
        let fields = entries
            .iter()
            .map(|(field, value, _)| ((*field).to_string(), value.clone()))
            .collect();
        let field_hlcs = entries
            .into_iter()
            .map(|(field, _, hlc)| (field.to_string(), hlc))
            .collect();
        SyncPlaintext::new(fields, field_hlcs).unwrap()
    }

    #[test]
    fn different_fields_from_concurrent_edits_are_both_preserved() {
        let local = plaintext(vec![("title", json!("A"), hlc(1, "device-a"))]);
        let incoming = plaintext(vec![("note", json!("B"), hlc(1, "device-b"))]);

        let merged = merge_lww(&local, &incoming).unwrap();

        assert_eq!(merged.plaintext.fields["title"], json!("A"));
        assert_eq!(merged.plaintext.fields["note"], json!("B"));
        assert!(merged.needs_repush());
    }

    #[test]
    fn same_field_conflict_uses_later_hlc() {
        let local = plaintext(vec![("title", json!("Old"), hlc(1, "device-a"))]);
        let incoming = plaintext(vec![("title", json!("New"), hlc(2, "device-b"))]);

        let merged = merge_lww(&local, &incoming).unwrap();

        assert_eq!(merged.plaintext.fields["title"], json!("New"));
        assert!(merged.local_won_fields.is_empty());
        assert!(merged.incoming_won_fields.contains("title"));
    }

    #[test]
    fn merge_is_commutative_for_field_values() {
        let a = plaintext(vec![
            ("title", json!("A"), hlc(1, "device-a")),
            ("priority", json!(2), hlc(3, "device-a")),
        ]);
        let b = plaintext(vec![
            ("title", json!("B"), hlc(2, "device-b")),
            ("note", json!("N"), hlc(1, "device-b")),
        ]);

        let ab = merge_lww(&a, &b).unwrap().plaintext;
        let ba = merge_lww(&b, &a).unwrap().plaintext;

        assert_eq!(ab, ba);
    }
}
