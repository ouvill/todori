-- Tenant is the only cryptographic boundary. Lists are ordinary encrypted
-- records and no longer own key generations or recipient packages.
DROP TABLE IF EXISTS list_key_generations;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'key_recipients'
          AND column_name = 'scope_kind'
    ) THEN
        DELETE FROM key_recipients WHERE scope_kind <> 1 OR list_id IS NOT NULL;
    END IF;
END
$$;

DROP INDEX IF EXISTS key_recipients_device_unique;
DROP INDEX IF EXISTS key_recipients_fingerprint_unique;

ALTER TABLE key_recipients
    DROP COLUMN IF EXISTS scope_kind,
    DROP COLUMN IF EXISTS list_id;

CREATE UNIQUE INDEX key_recipients_device_unique
    ON key_recipients (tenant_id, generation, device_id);
CREATE UNIQUE INDEX key_recipients_fingerprint_unique
    ON key_recipients (tenant_id, generation, recipient_key_fingerprint);

-- Shared / Enterprise lifecycle and authorization are not approved yet.
-- Keep the server schema fail-closed even if an internal caller bypasses the
-- removed organization routes.
ALTER TABLE tenants
    DROP CONSTRAINT IF EXISTS tenants_kind_check,
    DROP CONSTRAINT IF EXISTS tenants_personal_only;

ALTER TABLE tenants
    ADD CONSTRAINT tenants_personal_only
        CHECK (kind = 'personal');
