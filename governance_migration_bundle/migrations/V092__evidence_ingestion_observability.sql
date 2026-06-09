-- ============================================================================
-- BioDiscoveryAI Evidence Ingestion Observability
-- Migration: V098__evidence_ingestion_observability.sql
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS evidence.ingestion_requests (
    ingestion_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_request_id TEXT NOT NULL UNIQUE,
    idempotency_key TEXT UNIQUE,
    source_system TEXT NOT NULL,
    source_component TEXT,
    request_status TEXT NOT NULL DEFAULT 'received' CHECK (request_status IN ('received','validated','accepted','rejected','processing','completed','failed','duplicate')),
    actor_id TEXT REFERENCES registry.actors(actor_id),
    request_payload_hash TEXT,
    response_payload_hash TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT chk_ingestion_requests_time_quality CHECK (completed_at IS NULL OR completed_at >= received_at)
);

CREATE TABLE IF NOT EXISTS evidence.ingestion_attempts (
    ingestion_attempt_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingestion_request_id UUID NOT NULL REFERENCES evidence.ingestion_requests(ingestion_request_id) ON DELETE CASCADE,
    attempt_number INT NOT NULL CHECK (attempt_number > 0),
    attempt_status TEXT NOT NULL CHECK (attempt_status IN ('started','succeeded','failed','skipped')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    error_code TEXT,
    error_message TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE(ingestion_request_id, attempt_number),
    CONSTRAINT chk_ingestion_attempts_time_quality CHECK (ended_at IS NULL OR ended_at >= started_at)
);

ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS ingestion_status TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS api_request_id TEXT;
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS source_system TEXT;
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS ingestion_status TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS api_request_id TEXT;
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS source_system TEXT;
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

ALTER TABLE evidence.execution_steps ADD COLUMN IF NOT EXISTS ingestion_status TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE evidence.execution_steps ADD COLUMN IF NOT EXISTS api_request_id TEXT;
ALTER TABLE evidence.execution_steps ADD COLUMN IF NOT EXISTS source_system TEXT;
ALTER TABLE evidence.execution_steps ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE evidence.execution_steps ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

ALTER TABLE evidence.error_events ADD COLUMN IF NOT EXISTS ingestion_status TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE evidence.error_events ADD COLUMN IF NOT EXISTS api_request_id TEXT;
ALTER TABLE evidence.error_events ADD COLUMN IF NOT EXISTS source_system TEXT;
ALTER TABLE evidence.error_events ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE evidence.error_events ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS ingestion_status TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS api_request_id TEXT;
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS source_system TEXT;
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

ALTER TABLE reporting.execution_reports ADD COLUMN IF NOT EXISTS ingestion_status TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE reporting.execution_reports ADD COLUMN IF NOT EXISTS api_request_id TEXT;
ALTER TABLE reporting.execution_reports ADD COLUMN IF NOT EXISTS source_system TEXT;
ALTER TABLE reporting.execution_reports ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE reporting.execution_reports ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS chk_execution_runs_retry_count_nonnegative;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT chk_execution_runs_retry_count_nonnegative CHECK (retry_count >= 0) NOT VALID;
ALTER TABLE evidence.audit_events DROP CONSTRAINT IF EXISTS chk_audit_events_retry_count_nonnegative;
ALTER TABLE evidence.audit_events ADD CONSTRAINT chk_audit_events_retry_count_nonnegative CHECK (retry_count >= 0) NOT VALID;
ALTER TABLE evidence.execution_steps DROP CONSTRAINT IF EXISTS chk_execution_steps_retry_count_nonnegative;
ALTER TABLE evidence.execution_steps ADD CONSTRAINT chk_execution_steps_retry_count_nonnegative CHECK (retry_count >= 0) NOT VALID;
ALTER TABLE evidence.error_events DROP CONSTRAINT IF EXISTS chk_error_events_retry_count_nonnegative;
ALTER TABLE evidence.error_events ADD CONSTRAINT chk_error_events_retry_count_nonnegative CHECK (retry_count >= 0) NOT VALID;
ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS chk_artifacts_retry_count_nonnegative;
ALTER TABLE archive.artifacts ADD CONSTRAINT chk_artifacts_retry_count_nonnegative CHECK (retry_count >= 0) NOT VALID;
ALTER TABLE reporting.execution_reports DROP CONSTRAINT IF EXISTS chk_reports_retry_count_nonnegative;
ALTER TABLE reporting.execution_reports ADD CONSTRAINT chk_reports_retry_count_nonnegative CHECK (retry_count >= 0) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_ingestion_requests_status ON evidence.ingestion_requests(request_status, received_at);
CREATE INDEX IF NOT EXISTS idx_ingestion_requests_source ON evidence.ingestion_requests(source_system, received_at);
CREATE INDEX IF NOT EXISTS idx_ingestion_attempts_request ON evidence.ingestion_attempts(ingestion_request_id, attempt_number);
CREATE UNIQUE INDEX IF NOT EXISTS uq_execution_runs_idempotency_key ON evidence.execution_runs(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_audit_events_idempotency_key ON evidence.audit_events(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_execution_steps_idempotency_key ON evidence.execution_steps(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_error_events_idempotency_key ON evidence.error_events(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_artifacts_idempotency_key ON archive.artifacts(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_reports_idempotency_key ON reporting.execution_reports(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (98, '098', 'Evidence ingestion observability', 'V098__evidence_ingestion_observability.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;

