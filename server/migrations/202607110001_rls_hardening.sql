DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'taskveil_app') THEN
        CREATE ROLE taskveil_app NOLOGIN;
    END IF;
END
$$;

ALTER ROLE taskveil_app
    NOLOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

GRANT taskveil_app TO CURRENT_USER;
GRANT USAGE ON SCHEMA public TO taskveil_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO taskveil_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO taskveil_app;

ALTER TABLE user_key_generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_key_generations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_key_generations_isolation ON user_key_generations;
CREATE POLICY user_key_generations_isolation ON user_key_generations
    USING (user_id = NULLIF(current_setting('taskveil.user_id', true), '')::UUID)
    WITH CHECK (user_id = NULLIF(current_setting('taskveil.user_id', true), '')::UUID);

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenants_isolation ON tenants;
DROP POLICY IF EXISTS tenants_select ON tenants;
DROP POLICY IF EXISTS tenants_write ON tenants;
CREATE POLICY tenants_select ON tenants FOR SELECT
    USING (
        id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID
        OR (
            NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID IS NULL
            AND owner_user_id = NULLIF(current_setting('taskveil.user_id', true), '')::UUID
        )
    );
CREATE POLICY tenants_write ON tenants FOR ALL
    USING (id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE tenant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_members FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_members_isolation ON tenant_members;
DROP POLICY IF EXISTS tenant_members_select ON tenant_members;
DROP POLICY IF EXISTS tenant_members_write ON tenant_members;
CREATE POLICY tenant_members_select ON tenant_members FOR SELECT
    USING (
        tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID
        OR (
            NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID IS NULL
            AND user_id = NULLIF(current_setting('taskveil.user_id', true), '')::UUID
        )
    );
CREATE POLICY tenant_members_write ON tenant_members FOR ALL
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE tenant_seq ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_seq FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_seq_isolation ON tenant_seq;
CREATE POLICY tenant_seq_isolation ON tenant_seq
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE tenant_key_generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_key_generations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_key_generations_isolation ON tenant_key_generations;
CREATE POLICY tenant_key_generations_isolation ON tenant_key_generations
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE key_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE key_recipients FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS key_recipients_isolation ON key_recipients;
CREATE POLICY key_recipients_isolation ON key_recipients
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE key_generation_acks ENABLE ROW LEVEL SECURITY;
ALTER TABLE key_generation_acks FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS key_generation_acks_isolation ON key_generation_acks;
CREATE POLICY key_generation_acks_isolation ON key_generation_acks
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE sync_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sync_records_isolation ON sync_records;
CREATE POLICY sync_records_isolation ON sync_records
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);

ALTER TABLE sync_records_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sync_records_history_isolation ON sync_records_history;
CREATE POLICY sync_records_history_isolation ON sync_records_history
    USING (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('taskveil.tenant_id', true), '')::UUID);
