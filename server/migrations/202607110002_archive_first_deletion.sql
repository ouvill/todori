CREATE TABLE IF NOT EXISTS tenant_device_continuity (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    continuity_seq BIGINT NOT NULL DEFAULT 0 CHECK (continuity_seq >= 0),
    continuity_generation BIGINT NOT NULL DEFAULT 0 CHECK (continuity_generation >= 0),
    required_generation BIGINT NOT NULL DEFAULT 0 CHECK (required_generation >= 0),
    initialized BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, device_id),
    CHECK (continuity_generation <= required_generation)
);

CREATE TABLE IF NOT EXISTS device_resync_sessions (
    tenant_id UUID NOT NULL,
    device_id UUID NOT NULL,
    generation BIGINT NOT NULL CHECK (generation > 0),
    base_seq BIGINT NOT NULL CHECK (base_seq >= 0),
    base_cursor_collection TEXT CHECK (
        base_cursor_collection IS NULL OR base_cursor_collection IN ('lists', 'tasks')
    ),
    base_cursor_record_id UUID,
    base_complete BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, device_id, generation),
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES tenant_device_continuity(tenant_id, device_id) ON DELETE CASCADE,
    CHECK (
        (base_cursor_collection IS NULL AND base_cursor_record_id IS NULL)
        OR (base_cursor_collection IS NOT NULL AND base_cursor_record_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS continuity_closure_proofs (
    proof_id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL,
    device_id UUID NOT NULL,
    high_water BIGINT NOT NULL CHECK (high_water >= 0),
    generation BIGINT NOT NULL CHECK (generation >= 0),
    acknowledged_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, device_id)
        REFERENCES tenant_device_continuity(tenant_id, device_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS continuity_closure_proofs_device_idx
    ON continuity_closure_proofs(tenant_id, device_id, generation, high_water);

ALTER TABLE tenant_device_continuity ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_device_continuity FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_device_continuity_isolation ON tenant_device_continuity;
CREATE POLICY tenant_device_continuity_isolation ON tenant_device_continuity
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE device_resync_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_resync_sessions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS device_resync_sessions_isolation ON device_resync_sessions;
CREATE POLICY device_resync_sessions_isolation ON device_resync_sessions
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE continuity_closure_proofs ENABLE ROW LEVEL SECURITY;
ALTER TABLE continuity_closure_proofs FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS continuity_closure_proofs_isolation ON continuity_closure_proofs;
CREATE POLICY continuity_closure_proofs_isolation ON continuity_closure_proofs
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_device_continuity TO todori_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON device_resync_sessions TO todori_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON continuity_closure_proofs TO todori_app;

ALTER TABLE list_key_bundles
    ADD COLUMN IF NOT EXISTS deletion_seq BIGINT CHECK (deletion_seq > 0);
