DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'todori_app') THEN
        CREATE ROLE todori_app NOLOGIN;
    END IF;
END
$$;

ALTER ROLE todori_app
    NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

GRANT todori_app TO CURRENT_USER;
GRANT USAGE ON SCHEMA public TO todori_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO todori_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO todori_app;

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenants_isolation ON tenants;
DROP POLICY IF EXISTS tenants_select ON tenants;
DROP POLICY IF EXISTS tenants_write ON tenants;
CREATE POLICY tenants_select ON tenants FOR SELECT
    USING (
        id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID
        OR (
            NULLIF(current_setting('todori.tenant_id', true), '')::UUID IS NULL
            AND owner_user_id = NULLIF(current_setting('todori.user_id', true), '')::UUID
        )
    );
CREATE POLICY tenants_write ON tenants FOR ALL
    USING (id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE tenant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_members FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_members_isolation ON tenant_members;
DROP POLICY IF EXISTS tenant_members_select ON tenant_members;
DROP POLICY IF EXISTS tenant_members_write ON tenant_members;
CREATE POLICY tenant_members_select ON tenant_members FOR SELECT
    USING (
        tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID
        OR (
            NULLIF(current_setting('todori.tenant_id', true), '')::UUID IS NULL
            AND user_id = NULLIF(current_setting('todori.user_id', true), '')::UUID
        )
    );
CREATE POLICY tenant_members_write ON tenant_members FOR ALL
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE tenant_seq ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_seq FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_seq_isolation ON tenant_seq;
CREATE POLICY tenant_seq_isolation ON tenant_seq
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE tenant_key_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_key_bundles FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_key_bundles_isolation ON tenant_key_bundles;
CREATE POLICY tenant_key_bundles_isolation ON tenant_key_bundles
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE list_key_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_key_bundles FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS list_key_bundles_isolation ON list_key_bundles;
CREATE POLICY list_key_bundles_isolation ON list_key_bundles
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE sync_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sync_records_isolation ON sync_records;
CREATE POLICY sync_records_isolation ON sync_records
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);

ALTER TABLE sync_records_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sync_records_history_isolation ON sync_records_history;
CREATE POLICY sync_records_history_isolation ON sync_records_history
    USING (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('todori.tenant_id', true), '')::UUID);
