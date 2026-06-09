-- ============================================================================
-- BioDiscoveryAI Partition Index Reconciliation
-- Migration: V099__partition_index_reconciliation.sql
-- Purpose:
--   Reconcile index names after V095 legacy table renames. PostgreSQL index
--   names are schema-scoped, so indexes retained on *_legacy_unpartitioned can
--   block index creation on the new partitioned parent tables.
-- ============================================================================

BEGIN;

DO $$
BEGIN
    IF to_regclass('evidence.idx_audit_run') IS NOT NULL
       AND to_regclass('evidence.audit_events_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_audit_run RENAME TO idx_audit_run_legacy_unpartitioned;
    END IF;
    IF to_regclass('evidence.idx_audit_created') IS NOT NULL
       AND to_regclass('evidence.audit_events_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_audit_created RENAME TO idx_audit_created_legacy_unpartitioned;
    END IF;
    IF to_regclass('evidence.idx_audit_type') IS NOT NULL
       AND to_regclass('evidence.audit_events_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_audit_type RENAME TO idx_audit_type_legacy_unpartitioned;
    END IF;
    IF to_regclass('evidence.idx_steps_run') IS NOT NULL
       AND to_regclass('evidence.execution_steps_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_steps_run RENAME TO idx_steps_run_legacy_unpartitioned;
    END IF;
    IF to_regclass('evidence.idx_steps_created') IS NOT NULL
       AND to_regclass('evidence.execution_steps_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_steps_created RENAME TO idx_steps_created_legacy_unpartitioned;
    END IF;
    IF to_regclass('evidence.idx_errors_run') IS NOT NULL
       AND to_regclass('evidence.error_events_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_errors_run RENAME TO idx_errors_run_legacy_unpartitioned;
    END IF;
    IF to_regclass('evidence.idx_errors_created') IS NOT NULL
       AND to_regclass('evidence.error_events_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX evidence.idx_errors_created RENAME TO idx_errors_created_legacy_unpartitioned;
    END IF;
    IF to_regclass('archive.idx_artifacts_run') IS NOT NULL
       AND to_regclass('archive.artifacts_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX archive.idx_artifacts_run RENAME TO idx_artifacts_run_legacy_unpartitioned;
    END IF;
    IF to_regclass('archive.idx_artifacts_created') IS NOT NULL
       AND to_regclass('archive.artifacts_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX archive.idx_artifacts_created RENAME TO idx_artifacts_created_legacy_unpartitioned;
    END IF;
    IF to_regclass('archive.idx_artifacts_type') IS NOT NULL
       AND to_regclass('archive.artifacts_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX archive.idx_artifacts_type RENAME TO idx_artifacts_type_legacy_unpartitioned;
    END IF;
    IF to_regclass('reporting.idx_reports_run') IS NOT NULL
       AND to_regclass('reporting.execution_reports_legacy_unpartitioned') IS NOT NULL THEN
        ALTER INDEX reporting.idx_reports_run RENAME TO idx_reports_run_legacy_unpartitioned;
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

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (99, '099', 'Partition index reconciliation', 'V099__partition_index_reconciliation.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
