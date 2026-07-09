DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'sync_records'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'sync_records'
          AND column_name = 'revision_hlc'
    ) THEN
        DROP TABLE IF EXISTS sync_records_history;
        DROP TABLE sync_records;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS sync_records (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    record_id UUID NOT NULL,
    collection TEXT NOT NULL CHECK (collection IN ('lists', 'tasks')),
    seq BIGINT NOT NULL,
    revision_hlc TEXT NOT NULL CHECK (revision_hlc <> ''),
    mutation_hlc TEXT,
    delete_hlc TEXT,
    encrypted_blob BYTEA,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, record_id),
    UNIQUE (tenant_id, seq),
    CHECK (
        (
            mutation_hlc IS NOT NULL
            AND mutation_hlc <> ''
            AND revision_hlc >= mutation_hlc
            AND delete_hlc IS NULL
            AND encrypted_blob IS NOT NULL
            AND octet_length(encrypted_blob) > 0
        )
        OR
        (
            mutation_hlc IS NULL
            AND delete_hlc IS NOT NULL
            AND delete_hlc <> ''
            AND revision_hlc >= delete_hlc
            AND encrypted_blob IS NULL
        )
    )
);
CREATE INDEX IF NOT EXISTS sync_records_tenant_seq_idx ON sync_records(tenant_id, seq);

CREATE TABLE IF NOT EXISTS sync_records_history (
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    record_id UUID NOT NULL,
    collection TEXT NOT NULL CHECK (collection IN ('lists', 'tasks')),
    seq BIGINT NOT NULL,
    revision_hlc TEXT NOT NULL CHECK (revision_hlc <> ''),
    mutation_hlc TEXT,
    delete_hlc TEXT,
    encrypted_blob BYTEA,
    author_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    overwritten_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (
            mutation_hlc IS NOT NULL
            AND mutation_hlc <> ''
            AND revision_hlc >= mutation_hlc
            AND delete_hlc IS NULL
            AND encrypted_blob IS NOT NULL
            AND octet_length(encrypted_blob) > 0
        )
        OR
        (
            mutation_hlc IS NULL
            AND delete_hlc IS NOT NULL
            AND delete_hlc <> ''
            AND revision_hlc >= delete_hlc
            AND encrypted_blob IS NULL
        )
    )
);
CREATE INDEX IF NOT EXISTS sync_records_history_tenant_record_idx
    ON sync_records_history(tenant_id, record_id, overwritten_at DESC);

ALTER TABLE sync_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records_history ENABLE ROW LEVEL SECURITY;
