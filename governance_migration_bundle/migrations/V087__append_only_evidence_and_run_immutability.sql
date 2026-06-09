-- ============================================================================
-- BioDiscoveryAI Append-Only Evidence and Run Immutability
-- Migration: V093__append_only_evidence_and_run_immutability.sql
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION governance_admin.prevent_update_delete_unless_maintenance()
RETURNS TRIGGER AS $$
BEGIN
    IF current_setting('bdai.allow_append_only_maintenance', true) = 'on' THEN
        IF TG_OP = 'UPDATE' THEN
            RETURN NEW;
        END IF;
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Append-only protection: % is not allowed on %.%', TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_events_append_only ON evidence.audit_events;
CREATE TRIGGER trg_audit_events_append_only
BEFORE UPDATE OR DELETE ON evidence.audit_events
FOR EACH ROW EXECUTE FUNCTION governance_admin.prevent_update_delete_unless_maintenance();

DROP TRIGGER IF EXISTS trg_evidence_snapshots_append_only ON signing.evidence_snapshots;
CREATE TRIGGER trg_evidence_snapshots_append_only
BEFORE UPDATE OR DELETE ON signing.evidence_snapshots
FOR EACH ROW EXECUTE FUNCTION governance_admin.prevent_update_delete_unless_maintenance();

DROP TRIGGER IF EXISTS trg_artifacts_append_only ON archive.artifacts;
CREATE TRIGGER trg_artifacts_append_only
BEFORE UPDATE OR DELETE ON archive.artifacts
FOR EACH ROW EXECUTE FUNCTION governance_admin.prevent_update_delete_unless_maintenance();

CREATE OR REPLACE FUNCTION evidence.prevent_finalized_run_mutation()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Execution runs are retained for auditability and cannot be deleted.';
    END IF;

    IF OLD.run_state IN ('finalized','superseded','corrected','voided')
       AND current_setting('bdai.allow_controlled_correction', true) <> 'on' THEN
        RAISE EXCEPTION 'Run % is % and requires controlled correction for mutation.', OLD.run_id, OLD.run_state;
    END IF;

    IF NEW.run_state IN ('finalized','superseded','corrected','voided') AND NEW.finalized_at IS NULL THEN
        NEW.finalized_at := now();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_execution_runs_finalized_guard ON evidence.execution_runs;
CREATE TRIGGER trg_execution_runs_finalized_guard
BEFORE UPDATE OR DELETE ON evidence.execution_runs
FOR EACH ROW EXECUTE FUNCTION evidence.prevent_finalized_run_mutation();

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (93, '093', 'Append-only evidence and run immutability', 'V093__append_only_evidence_and_run_immutability.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
