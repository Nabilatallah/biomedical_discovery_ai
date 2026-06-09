-- ============================================================================
-- BioDiscoveryAI Evidence Schema Migration History
-- Migration: V091__evidence_schema_migration_history.sql
-- Purpose:
--   Add Flyway/Liquibase-style migration state tracking for the evidence and
--   governance SQL chain.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_admin;

CREATE TABLE IF NOT EXISTS governance_admin.schema_migrations (
    installed_rank      INT PRIMARY KEY,
    version             TEXT NOT NULL UNIQUE,
    description         TEXT NOT NULL,
    script              TEXT NOT NULL UNIQUE,
    checksum_sha256     TEXT,
    installed_by        TEXT NOT NULL DEFAULT current_user,
    installed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    execution_time_ms   INT,
    success             BOOLEAN NOT NULL DEFAULT true,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT chk_schema_migrations_rank_positive CHECK (installed_rank > 0),
    CONSTRAINT chk_schema_migrations_execution_time_nonnegative CHECK (execution_time_ms IS NULL OR execution_time_ms >= 0)
);

CREATE TABLE IF NOT EXISTS governance_admin.schema_migration_events (
    migration_event_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version             TEXT NOT NULL,
    script              TEXT NOT NULL,
    event_type          TEXT NOT NULL CHECK (event_type IN ('baseline','apply_started','apply_completed','apply_failed','checksum_recorded','manual_correction')),
    event_message       TEXT,
    actor               TEXT NOT NULL DEFAULT current_user,
    payload             JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO governance_admin.schema_migrations (
    installed_rank, version, description, script, success, metadata
)
VALUES
    (1, '001-090', 'Baseline SQL chain present before migration ledger introduction', 'V001_to_V090_baseline', true, '{"baseline":true,"note":"Existing SQL folder chain through V090 was present before schema_migrations tracking."}'::jsonb),
    (91, '091', 'Evidence schema migration history', 'V091__evidence_schema_migration_history.sql', true, '{"introduced_by":"hardening_layer"}'::jsonb)
ON CONFLICT (version) DO UPDATE SET
    description = EXCLUDED.description,
    script = EXCLUDED.script,
    success = EXCLUDED.success,
    metadata = governance_admin.schema_migrations.metadata || EXCLUDED.metadata;

INSERT INTO governance_admin.schema_migration_events (version, script, event_type, event_message)
VALUES
    ('001-090', 'V001_to_V090_baseline', 'baseline', 'Registered pre-existing SQL migration baseline.'),
    ('091', 'V091__evidence_schema_migration_history.sql', 'apply_completed', 'Migration ledger created.')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE VIEW governance_admin.current_schema_version AS
SELECT version, description, script, installed_at, installed_by, success
FROM governance_admin.schema_migrations
WHERE success = true
ORDER BY installed_rank DESC
LIMIT 1;

COMMENT ON TABLE governance_admin.schema_migrations IS
'Ledger of applied SQL migrations. Existing V001-V090 migrations are recorded as a baseline; future migrations should insert one row each.';

COMMIT;
