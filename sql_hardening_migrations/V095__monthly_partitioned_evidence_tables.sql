-- ============================================================================
-- BioDiscoveryAI Monthly Partitioned Evidence Tables
-- Migration: V095__monthly_partitioned_evidence_tables.sql
-- Purpose:
--   Convert high-growth evidence tables to monthly range partitioning on
--   created_at while preserving the original table names used by tools.
--   Legacy unpartitioned tables are retained with *_legacy_unpartitioned names.
-- ============================================================================

BEGIN;

SET LOCAL bdai.allow_append_only_maintenance = 'on';

CREATE OR REPLACE FUNCTION governance_admin.ensure_monthly_partition(
    p_parent_schema TEXT,
    p_parent_table TEXT,
    p_partition_schema TEXT,
    p_base_name TEXT,
    p_start_date DATE
) RETURNS VOID AS $$
DECLARE
    v_partition_name TEXT;
    v_end_date DATE;
BEGIN
    v_partition_name := p_base_name || '_' || to_char(p_start_date, 'YYYY_MM');
    v_end_date := (p_start_date + INTERVAL '1 month')::DATE;
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
        p_partition_schema, v_partition_name, p_parent_schema, p_parent_table, p_start_date, v_end_date
    );
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_start DATE;
BEGIN
    IF to_regclass('evidence.audit_events') IS NOT NULL
       AND (SELECT c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'evidence' AND c.relname = 'audit_events') <> 'p'
       AND to_regclass('evidence.audit_events_legacy_unpartitioned') IS NULL THEN
        ALTER TABLE evidence.audit_events RENAME TO audit_events_legacy_unpartitioned;
    END IF;

    CREATE TABLE IF NOT EXISTS evidence.audit_events (
        audit_event_id UUID DEFAULT gen_random_uuid(),
        run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
        event_type TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT,
        actor TEXT,
        previous_hash TEXT,
        event_hash TEXT,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        event_sequence BIGINT NOT NULL,
        canonical_event JSONB NOT NULL DEFAULT '{}'::jsonb,
        hash_algorithm TEXT NOT NULL DEFAULT 'sha256-canonical-json-v1',
        PRIMARY KEY (audit_event_id, created_at),
        UNIQUE (run_id, event_sequence, created_at),
        CONSTRAINT chk_audit_events_sequence_positive CHECK (event_sequence > 0)
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE IF NOT EXISTS evidence.audit_events_default PARTITION OF evidence.audit_events DEFAULT;

    IF to_regclass('evidence.execution_steps') IS NOT NULL
       AND (SELECT c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'evidence' AND c.relname = 'execution_steps') <> 'p'
       AND to_regclass('evidence.execution_steps_legacy_unpartitioned') IS NULL THEN
        ALTER TABLE evidence.execution_steps RENAME TO execution_steps_legacy_unpartitioned;
    END IF;

    CREATE TABLE IF NOT EXISTS evidence.execution_steps (
        step_event_id UUID DEFAULT gen_random_uuid(),
        run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
        step_id TEXT NOT NULL,
        step_title TEXT NOT NULL,
        step_purpose TEXT,
        status TEXT NOT NULL,
        started_at TIMESTAMPTZ,
        ended_at TIMESTAMPTZ,
        duration_seconds INTEGER,
        evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (step_event_id, created_at),
        CONSTRAINT chk_execution_steps_duration_nonnegative CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
        CONSTRAINT chk_execution_steps_time_quality CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at)
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE IF NOT EXISTS evidence.execution_steps_default PARTITION OF evidence.execution_steps DEFAULT;

    IF to_regclass('evidence.error_events') IS NOT NULL
       AND (SELECT c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'evidence' AND c.relname = 'error_events') <> 'p'
       AND to_regclass('evidence.error_events_legacy_unpartitioned') IS NULL THEN
        ALTER TABLE evidence.error_events RENAME TO error_events_legacy_unpartitioned;
    END IF;

    CREATE TABLE IF NOT EXISTS evidence.error_events (
        error_event_id UUID DEFAULT gen_random_uuid(),
        run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
        error_code TEXT,
        error_message TEXT NOT NULL,
        severity TEXT NOT NULL DEFAULT 'High',
        stack_trace TEXT,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (error_event_id, created_at)
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE IF NOT EXISTS evidence.error_events_default PARTITION OF evidence.error_events DEFAULT;

    IF to_regclass('archive.artifacts') IS NOT NULL
       AND (SELECT c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'archive' AND c.relname = 'artifacts') <> 'p'
       AND to_regclass('archive.artifacts_legacy_unpartitioned') IS NULL THEN
        ALTER TABLE archive.artifacts RENAME TO artifacts_legacy_unpartitioned;
    END IF;

    CREATE TABLE IF NOT EXISTS archive.artifacts (
        artifact_id UUID DEFAULT gen_random_uuid(),
        run_id TEXT REFERENCES evidence.execution_runs(run_id) ON DELETE SET NULL,
        artifact_name TEXT NOT NULL,
        artifact_type TEXT NOT NULL REFERENCES registry.artifact_types(artifact_type_id),
        storage_backend TEXT NOT NULL REFERENCES registry.storage_backends(storage_backend_code),
        storage_uri TEXT NOT NULL,
        sha256 TEXT NOT NULL,
        size_bytes BIGINT,
        content_type TEXT,
        criticality TEXT NOT NULL DEFAULT 'High' REFERENCES registry.criticality_levels(criticality_code),
        retention_period TEXT NOT NULL DEFAULT '7_years' REFERENCES registry.retention_periods(retention_period_code),
        legal_hold BOOLEAN NOT NULL DEFAULT false,
        immutable BOOLEAN NOT NULL DEFAULT true,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (artifact_id, created_at),
        CONSTRAINT chk_artifact_sha256 CHECK (sha256 ~ '^[a-fA-F0-9]{64}$'),
        CONSTRAINT chk_artifacts_size_nonnegative CHECK (size_bytes IS NULL OR size_bytes >= 0)
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE IF NOT EXISTS archive.artifacts_default PARTITION OF archive.artifacts DEFAULT;

    IF to_regclass('reporting.execution_reports') IS NOT NULL
       AND (SELECT c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'reporting' AND c.relname = 'execution_reports') <> 'p'
       AND to_regclass('reporting.execution_reports_legacy_unpartitioned') IS NULL THEN
        ALTER TABLE reporting.execution_reports RENAME TO execution_reports_legacy_unpartitioned;
    END IF;

    CREATE TABLE IF NOT EXISTS reporting.execution_reports (
        report_id UUID DEFAULT gen_random_uuid(),
        run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
        report_type TEXT NOT NULL,
        report_markdown TEXT,
        report_uri TEXT,
        report_hash TEXT,
        rendered_format TEXT,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (report_id, created_at)
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE IF NOT EXISTS reporting.execution_reports_default PARTITION OF reporting.execution_reports DEFAULT;

    FOR v_start IN SELECT generate_series(DATE '2026-01-01', DATE '2031-12-01', INTERVAL '1 month')::DATE LOOP
        PERFORM governance_admin.ensure_monthly_partition('evidence','audit_events','evidence','audit_events',v_start);
        PERFORM governance_admin.ensure_monthly_partition('evidence','execution_steps','evidence','execution_steps',v_start);
        PERFORM governance_admin.ensure_monthly_partition('evidence','error_events','evidence','error_events',v_start);
        PERFORM governance_admin.ensure_monthly_partition('archive','artifacts','archive','artifacts',v_start);
        PERFORM governance_admin.ensure_monthly_partition('reporting','execution_reports','reporting','execution_reports',v_start);
    END LOOP;

    IF to_regclass('evidence.audit_events_legacy_unpartitioned') IS NOT NULL THEN
        EXECUTE 'INSERT INTO evidence.audit_events SELECT * FROM evidence.audit_events_legacy_unpartitioned l WHERE NOT EXISTS (SELECT 1 FROM evidence.audit_events n WHERE n.audit_event_id = l.audit_event_id)';
    END IF;
    IF to_regclass('evidence.execution_steps_legacy_unpartitioned') IS NOT NULL THEN
        EXECUTE 'INSERT INTO evidence.execution_steps SELECT * FROM evidence.execution_steps_legacy_unpartitioned l WHERE NOT EXISTS (SELECT 1 FROM evidence.execution_steps n WHERE n.step_event_id = l.step_event_id)';
    END IF;
    IF to_regclass('evidence.error_events_legacy_unpartitioned') IS NOT NULL THEN
        EXECUTE 'INSERT INTO evidence.error_events SELECT * FROM evidence.error_events_legacy_unpartitioned l WHERE NOT EXISTS (SELECT 1 FROM evidence.error_events n WHERE n.error_event_id = l.error_event_id)';
    END IF;
    IF to_regclass('archive.artifacts_legacy_unpartitioned') IS NOT NULL THEN
        EXECUTE 'INSERT INTO archive.artifacts SELECT * FROM archive.artifacts_legacy_unpartitioned l WHERE NOT EXISTS (SELECT 1 FROM archive.artifacts n WHERE n.artifact_id = l.artifact_id)';
    END IF;
    IF to_regclass('reporting.execution_reports_legacy_unpartitioned') IS NOT NULL THEN
        EXECUTE 'INSERT INTO reporting.execution_reports SELECT * FROM reporting.execution_reports_legacy_unpartitioned l WHERE NOT EXISTS (SELECT 1 FROM reporting.execution_reports n WHERE n.report_id = l.report_id)';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_audit_run ON evidence.audit_events(run_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON evidence.audit_events(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_type ON evidence.audit_events(event_type);
CREATE INDEX IF NOT EXISTS idx_audit_events_run_sequence ON evidence.audit_events(run_id, event_sequence);
CREATE INDEX IF NOT EXISTS idx_steps_run ON evidence.execution_steps(run_id);
CREATE INDEX IF NOT EXISTS idx_steps_created ON evidence.execution_steps(created_at);
CREATE INDEX IF NOT EXISTS idx_errors_run ON evidence.error_events(run_id);
CREATE INDEX IF NOT EXISTS idx_errors_created ON evidence.error_events(created_at);
CREATE INDEX IF NOT EXISTS idx_artifacts_run ON archive.artifacts(run_id);
CREATE INDEX IF NOT EXISTS idx_artifacts_created ON archive.artifacts(created_at);
CREATE INDEX IF NOT EXISTS idx_artifacts_type ON archive.artifacts(artifact_type);
CREATE INDEX IF NOT EXISTS idx_reports_run ON reporting.execution_reports(run_id);

DROP TRIGGER IF EXISTS trg_audit_events_hash ON evidence.audit_events;
CREATE TRIGGER trg_audit_events_hash
BEFORE INSERT ON evidence.audit_events
FOR EACH ROW EXECUTE FUNCTION evidence.audit_events_hash_trigger();

DROP TRIGGER IF EXISTS trg_audit_events_append_only ON evidence.audit_events;
CREATE TRIGGER trg_audit_events_append_only
BEFORE UPDATE OR DELETE ON evidence.audit_events
FOR EACH ROW EXECUTE FUNCTION governance_admin.prevent_update_delete_unless_maintenance();

DROP TRIGGER IF EXISTS trg_artifacts_append_only ON archive.artifacts;
CREATE TRIGGER trg_artifacts_append_only
BEFORE UPDATE OR DELETE ON archive.artifacts
FOR EACH ROW EXECUTE FUNCTION governance_admin.prevent_update_delete_unless_maintenance();

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (95, '095', 'Monthly partitioned evidence tables', 'V095__monthly_partitioned_evidence_tables.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
