CREATE TABLE IF NOT EXISTS user_key_generations (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    generation BIGINT NOT NULL CHECK (generation > 0),
    suite_id SMALLINT NOT NULL CHECK (suite_id = 2),
    status TEXT NOT NULL CHECK (status IN ('prepared', 'active', 'migrating', 'retired')),
    wrapper_revision BIGINT NOT NULL CHECK (wrapper_revision > 0),
    wrapped_mk_by_password BYTEA NOT NULL,
    wrapped_mk_by_recovery BYTEA NOT NULL,
    account_root_public BYTEA NOT NULL,
    wrapped_account_root_private BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, generation)
);
CREATE UNIQUE INDEX IF NOT EXISTS user_key_generations_active_unique
    ON user_key_generations(user_id)
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS tenant_key_generations (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    generation BIGINT NOT NULL CHECK (generation > 0),
    suite_id SMALLINT NOT NULL CHECK (suite_id = 2),
    status TEXT NOT NULL CHECK (status IN ('prepared', 'active', 'migrating', 'retired')),
    minimum_write_generation BIGINT NOT NULL CHECK (
        minimum_write_generation > 0 AND minimum_write_generation <= generation
    ),
    signed_manifest BYTEA NOT NULL CHECK (octet_length(signed_manifest) >= 107),
    prepared_manifest BYTEA CHECK (prepared_manifest IS NULL OR octet_length(prepared_manifest) >= 107),
    wrapped_tenant_root_dek BYTEA NOT NULL,
    live_heads_remaining BIGINT NOT NULL DEFAULT 0 CHECK (live_heads_remaining >= 0),
    activated_at TIMESTAMPTZ,
    migration_completed_at TIMESTAMPTZ,
    history_retain_until TIMESTAMPTZ,
    retired_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, generation)
);
CREATE UNIQUE INDEX IF NOT EXISTS tenant_key_generations_current_unique
    ON tenant_key_generations(tenant_id)
    WHERE status = 'active';

CREATE TABLE IF NOT EXISTS key_recipients (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    generation BIGINT NOT NULL CHECK (generation > 0),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    recipient_key_fingerprint BYTEA NOT NULL CHECK (octet_length(recipient_key_fingerprint) = 32),
    wrapped_dek BYTEA NOT NULL,
    continuity_acked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS key_recipients_device_unique
    ON key_recipients (
        tenant_id,
        generation,
        device_id
    );
CREATE UNIQUE INDEX IF NOT EXISTS key_recipients_fingerprint_unique
    ON key_recipients (
        tenant_id,
        generation,
        recipient_key_fingerprint
    );

CREATE TABLE IF NOT EXISTS key_generation_acks (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    generation BIGINT NOT NULL CHECK (generation > 0),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    acknowledged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, generation, device_id)
);
