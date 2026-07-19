CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE users DROP COLUMN IF EXISTS plan;

CREATE TABLE IF NOT EXISTS billing_customers (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL DEFAULT 'revenuecat' CHECK (provider = 'revenuecat'),
    provider_app_user_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    sandbox_refresh_token UUID,
    production_refresh_token UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE billing_customers ADD COLUMN IF NOT EXISTS sandbox_refresh_token UUID;
ALTER TABLE billing_customers ADD COLUMN IF NOT EXISTS production_refresh_token UUID;

INSERT INTO billing_customers (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS billing_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL CHECK (provider = 'revenuecat'),
    project_id TEXT NOT NULL,
    provider_event_id TEXT NOT NULL,
    app_id TEXT NOT NULL,
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    provider_app_user_id UUID NOT NULL,
    event_type TEXT,
    store TEXT,
    store_product_identifier TEXT,
    store_transaction_identifier TEXT,
    store_original_transaction_identifier TEXT,
    price NUMERIC(12, 4),
    currency CHAR(3),
    country_code CHAR(2),
    payload_sha256 BYTEA NOT NULL CHECK (octet_length(payload_sha256) = 32),
    processing_status TEXT NOT NULL DEFAULT 'processing'
        CHECK (processing_status IN ('processing', 'processed', 'failed')),
    processing_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processing_error_code TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,
    UNIQUE (provider, project_id, provider_event_id)
);

CREATE INDEX IF NOT EXISTS billing_events_customer_idx
    ON billing_events(provider_app_user_id, received_at DESC);

CREATE TABLE IF NOT EXISTS billing_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider = 'revenuecat'),
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    provider_subscription_id TEXT NOT NULL,
    store_transaction_identifier TEXT,
    store_original_transaction_identifier TEXT,
    store_product_identifier TEXT NOT NULL,
    provider_product_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('trial', 'active', 'grace', 'expired', 'revoked')),
    gives_access BOOLEAN NOT NULL DEFAULT FALSE,
    current_period_ends_at TIMESTAMPTZ,
    access_expires_at TIMESTAMPTZ,
    will_renew BOOLEAN,
    revocation_reason TEXT,
    provider_observed_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, environment, provider_subscription_id)
);

CREATE INDEX IF NOT EXISTS billing_subscriptions_user_environment_idx
    ON billing_subscriptions(user_id, environment, updated_at DESC);

CREATE TABLE IF NOT EXISTS account_entitlements (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    lookup_key TEXT NOT NULL CHECK (lookup_key = 'pro'),
    status TEXT NOT NULL DEFAULT 'free'
        CHECK (status IN ('free', 'trial', 'active', 'grace', 'expired', 'revoked')),
    gives_access BOOLEAN NOT NULL DEFAULT FALSE,
    source_subscription_id UUID REFERENCES billing_subscriptions(id) ON DELETE SET NULL,
    store_product_identifier TEXT,
    expires_at TIMESTAMPTZ,
    grace_expires_at TIMESTAMPTZ,
    will_renew BOOLEAN,
    provider_observed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, environment, lookup_key)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON billing_customers TO taskveil_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing_events TO taskveil_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing_subscriptions TO taskveil_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON account_entitlements TO taskveil_app;
