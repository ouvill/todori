//! Account membership and Tenant boundary invariants.
//!
//! Tenant is the cryptographic, synchronization, sharing, and local-database
//! boundary. Shared Tenant lifecycle is deliberately not enabled until its
//! invitation, authorization, and key-rotation protocol is approved.

use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TenantKind {
    Personal,
    Shared,
    Enterprise,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Tenant {
    pub id: Uuid,
    pub kind: TenantKind,
    pub created_at: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TenantRole {
    Owner,
    Editor,
    Viewer,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TenantMembershipState {
    Invited,
    Active,
    Suspended,
    Removed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TenantMembership {
    pub tenant_id: Uuid,
    pub account_id: Uuid,
    pub role: TenantRole,
    pub state: TenantMembershipState,
    pub activated_at: Option<i64>,
    pub removed_at: Option<i64>,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum TenantBoundaryError {
    #[error("Tenant or Account identity is invalid")]
    InvalidIdentity,
    #[error("Shared Tenant lifecycle is not enabled")]
    SharedTenantDisabled,
    #[error("Personal Tenant must have exactly one active owner")]
    InvalidPersonalOwner,
    #[error("Tenant membership belongs to another Tenant")]
    CrossTenantMembership,
    #[error("Tenant membership timestamps do not match its state")]
    InvalidMembershipState,
}

impl TenantMembership {
    pub fn validate(&self) -> Result<(), TenantBoundaryError> {
        if self.tenant_id.is_nil() || self.account_id.is_nil() {
            return Err(TenantBoundaryError::InvalidIdentity);
        }
        let timestamps_valid = match self.state {
            TenantMembershipState::Invited => {
                self.activated_at.is_none() && self.removed_at.is_none()
            }
            TenantMembershipState::Active | TenantMembershipState::Suspended => {
                self.activated_at.is_some() && self.removed_at.is_none()
            }
            TenantMembershipState::Removed => {
                self.activated_at.is_some() && self.removed_at.is_some()
            }
        };
        if !timestamps_valid {
            return Err(TenantBoundaryError::InvalidMembershipState);
        }
        Ok(())
    }
}

impl Tenant {
    /// Validates the only Tenant configuration enabled by this release.
    pub fn validate_current_release(
        &self,
        memberships: &[TenantMembership],
    ) -> Result<(), TenantBoundaryError> {
        if self.id.is_nil() {
            return Err(TenantBoundaryError::InvalidIdentity);
        }
        if self.kind != TenantKind::Personal {
            return Err(TenantBoundaryError::SharedTenantDisabled);
        }
        for membership in memberships {
            membership.validate()?;
            if membership.tenant_id != self.id {
                return Err(TenantBoundaryError::CrossTenantMembership);
            }
        }
        let active_owners = memberships
            .iter()
            .filter(|membership| {
                membership.state == TenantMembershipState::Active
                    && membership.role == TenantRole::Owner
            })
            .count();
        if memberships.len() != 1 || active_owners != 1 {
            return Err(TenantBoundaryError::InvalidPersonalOwner);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn personal_fixture() -> (Tenant, TenantMembership) {
        let tenant_id = Uuid::now_v7();
        (
            Tenant {
                id: tenant_id,
                kind: TenantKind::Personal,
                created_at: 1,
            },
            TenantMembership {
                tenant_id,
                account_id: Uuid::now_v7(),
                role: TenantRole::Owner,
                state: TenantMembershipState::Active,
                activated_at: Some(1),
                removed_at: None,
            },
        )
    }

    #[test]
    fn personal_tenant_requires_exactly_one_active_owner() {
        let (tenant, owner) = personal_fixture();
        assert_eq!(
            tenant.validate_current_release(std::slice::from_ref(&owner)),
            Ok(())
        );
        assert_eq!(
            tenant.validate_current_release(&[]),
            Err(TenantBoundaryError::InvalidPersonalOwner)
        );
        let mut second = owner;
        second.account_id = Uuid::now_v7();
        assert_eq!(
            tenant.validate_current_release(&[second.clone(), second]),
            Err(TenantBoundaryError::InvalidPersonalOwner)
        );
    }

    #[test]
    fn shared_tenant_is_fail_closed_until_protocol_is_approved() {
        let (mut tenant, owner) = personal_fixture();
        tenant.kind = TenantKind::Shared;
        assert_eq!(
            tenant.validate_current_release(&[owner]),
            Err(TenantBoundaryError::SharedTenantDisabled)
        );
    }

    #[test]
    fn membership_cannot_cross_tenant_boundary() {
        let (tenant, mut owner) = personal_fixture();
        owner.tenant_id = Uuid::now_v7();
        assert_eq!(
            tenant.validate_current_release(&[owner]),
            Err(TenantBoundaryError::CrossTenantMembership)
        );
    }
}
