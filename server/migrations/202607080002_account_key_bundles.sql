CREATE TABLE IF NOT EXISTS user_key_bundles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    wrapped_master_key_by_password BYTEA NOT NULL,
    wrapped_master_key_by_recovery BYTEA NOT NULL,
    user_public_key BYTEA NOT NULL CHECK (octet_length(user_public_key) = 32),
    wrapped_user_secret_key BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_key_bundles (
    tenant_id UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    wrapped_tenant_root_dek BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS list_key_bundles (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    list_id UUID NOT NULL,
    wrapped_list_dek BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, list_id)
);

CREATE INDEX IF NOT EXISTS list_key_bundles_tenant_id_idx
    ON list_key_bundles(tenant_id);
