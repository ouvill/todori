CREATE TABLE IF NOT EXISTS opaque_server_setup (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    opaque_suite_id SMALLINT NOT NULL CHECK (opaque_suite_id = 2),
    setup BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email TEXT NOT NULL,
    opaque_suite_id SMALLINT NOT NULL CHECK (opaque_suite_id = 2),
    opaque_record BYTEA NOT NULL,
    account_root_public BYTEA NOT NULL,
    device_roster_revision BIGINT NOT NULL DEFAULT 0 CHECK (device_roster_revision >= 0),
    plan TEXT NOT NULL DEFAULT 'free',
    region TEXT NOT NULL DEFAULT 'eu-central-1',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_unique ON users ((lower(email)));

CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name TEXT NOT NULL,
    certificate BYTEA,
    certificate_fingerprint BYTEA CHECK (
        certificate_fingerprint IS NULL OR octet_length(certificate_fingerprint) = 48
    ),
    enrollment_challenge BYTEA CHECK (
        enrollment_challenge IS NULL OR octet_length(enrollment_challenge) = 32
    ),
    enrollment_challenge_expires_at TIMESTAMPTZ,
    certified_at TIMESTAMPTZ,
    last_pull_at TIMESTAMPTZ,
    key_expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revocation_revision BIGINT CHECK (
        revocation_revision IS NULL OR revocation_revision > 0
    ),
    signed_revocation BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS devices_user_id_idx ON devices(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS devices_user_revocation_revision_unique
    ON devices(user_id, revocation_revision)
    WHERE revocation_revision IS NOT NULL;

CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('personal', 'org')),
    owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rotation_required BOOLEAN NOT NULL DEFAULT FALSE,
    region TEXT NOT NULL DEFAULT 'eu-central-1',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tenants_owner_user_id_idx ON tenants(owner_user_id);

CREATE TABLE IF NOT EXISTS tenant_members (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
    verification_state TEXT NOT NULL DEFAULT 'unverified'
        CHECK (verification_state IN ('unverified', 'verified')),
    safety_number_digest BYTEA CHECK (
        safety_number_digest IS NULL OR octet_length(safety_number_digest) = 48
    ),
    safety_owner_root_fingerprint BYTEA CHECK (
        safety_owner_root_fingerprint IS NULL
        OR octet_length(safety_owner_root_fingerprint) = 48
    ),
    safety_member_root_fingerprint BYTEA CHECK (
        safety_member_root_fingerprint IS NULL
        OR octet_length(safety_member_root_fingerprint) = 48
    ),
    owner_confirmed_at TIMESTAMPTZ,
    member_confirmed_at TIMESTAMPTZ,
    verified_at TIMESTAMPTZ,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, user_id)
);
CREATE INDEX IF NOT EXISTS tenant_members_user_id_idx ON tenant_members(user_id);

CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    token_hash BYTEA NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS sessions_user_device_idx ON sessions(user_id, device_id);

CREATE TABLE IF NOT EXISTS opaque_registration_states (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    tenant_id UUID NOT NULL,
    device_id UUID NOT NULL,
    device_challenge BYTEA NOT NULL CHECK (octet_length(device_challenge) = 32),
    email TEXT NOT NULL,
    device_name TEXT NOT NULL,
    opaque_suite_id SMALLINT NOT NULL CHECK (opaque_suite_id = 2),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS opaque_registration_states_expires_at_idx ON opaque_registration_states(expires_at);

CREATE TABLE IF NOT EXISTS opaque_login_states (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL,
    device_id UUID NOT NULL,
    device_challenge BYTEA NOT NULL CHECK (octet_length(device_challenge) = 32),
    device_name TEXT NOT NULL,
    opaque_suite_id SMALLINT NOT NULL CHECK (opaque_suite_id = 2),
    server_login_state BYTEA NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS opaque_login_states_expires_at_idx ON opaque_login_states(expires_at);

CREATE TABLE IF NOT EXISTS tenant_seq (
    tenant_id UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    last_seq BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_records (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    record_id UUID NOT NULL,
    collection TEXT NOT NULL,
    seq BIGINT NOT NULL,
    hlc TEXT NOT NULL,
    encrypted_blob BYTEA NOT NULL,
    deleted BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, record_id),
    UNIQUE (tenant_id, seq)
);
CREATE INDEX IF NOT EXISTS sync_records_tenant_seq_idx ON sync_records(tenant_id, seq);

CREATE TABLE IF NOT EXISTS sync_records_history (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    record_id UUID NOT NULL,
    collection TEXT NOT NULL,
    seq BIGINT NOT NULL,
    hlc TEXT NOT NULL,
    encrypted_blob BYTEA NOT NULL,
    deleted BOOLEAN NOT NULL,
    author_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    overwritten_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sync_records_history_tenant_record_idx
    ON sync_records_history(tenant_id, record_id, overwritten_at DESC);

ALTER TABLE sync_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records_history ENABLE ROW LEVEL SECURITY;
