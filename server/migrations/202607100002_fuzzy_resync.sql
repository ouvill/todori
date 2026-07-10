ALTER TABLE tenant_seq
    ADD COLUMN IF NOT EXISTS gc_horizon_seq BIGINT NOT NULL DEFAULT 0
        CHECK (gc_horizon_seq >= 0);
