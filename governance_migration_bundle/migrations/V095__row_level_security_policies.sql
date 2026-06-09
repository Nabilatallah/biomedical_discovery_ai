-- ============================================================================
-- BioDiscoveryAI Row-Level Security Policies
-- Migration: V101__row_level_security_policies.sql
-- Purpose:
--   Add database-native row-level security hooks. Policies use the optional
--   bdai.current_actor_id session setting and allow auditor/schema-admin roles
--   broad read access while constraining writer/service writes to actor-owned
--   or actor-unspecified rows.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION governance_admin.current_actor_id()
RETURNS TEXT AS $$
BEGIN
    RETURN NULLIF(current_setting('bdai.current_actor_id', true), '');
END;
$$ LANGUAGE plpgsql STABLE;

ALTER TABLE evidence.execution_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidence.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidence.execution_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidence.error_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE archive.artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE signing.evidence_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE reporting.execution_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE retention.legal_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE retention.retention_enforcement_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE retention.disposition_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_execution_runs_read ON evidence.execution_runs;
CREATE POLICY pol_execution_runs_read ON evidence.execution_runs
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_execution_runs_write_actor ON evidence.execution_runs;
CREATE POLICY pol_execution_runs_write_actor ON evidence.execution_runs
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (actor_id IS NULL OR actor_id = governance_admin.current_actor_id() OR governance_admin.current_actor_id() IS NULL);

DROP POLICY IF EXISTS pol_audit_events_read ON evidence.audit_events;
CREATE POLICY pol_audit_events_read ON evidence.audit_events
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_audit_events_write_actor ON evidence.audit_events;
CREATE POLICY pol_audit_events_write_actor ON evidence.audit_events
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (actor_id IS NULL OR actor_id = governance_admin.current_actor_id() OR governance_admin.current_actor_id() IS NULL);

DROP POLICY IF EXISTS pol_execution_steps_read ON evidence.execution_steps;
CREATE POLICY pol_execution_steps_read ON evidence.execution_steps
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_execution_steps_insert ON evidence.execution_steps;
CREATE POLICY pol_execution_steps_insert ON evidence.execution_steps
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (true);

DROP POLICY IF EXISTS pol_error_events_read ON evidence.error_events;
CREATE POLICY pol_error_events_read ON evidence.error_events
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_error_events_insert ON evidence.error_events;
CREATE POLICY pol_error_events_insert ON evidence.error_events
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (true);

DROP POLICY IF EXISTS pol_artifacts_read ON archive.artifacts;
CREATE POLICY pol_artifacts_read ON archive.artifacts
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_artifacts_insert ON archive.artifacts;
CREATE POLICY pol_artifacts_insert ON archive.artifacts
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (true);

DROP POLICY IF EXISTS pol_signing_read ON signing.evidence_snapshots;
CREATE POLICY pol_signing_read ON signing.evidence_snapshots
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_signing_insert ON signing.evidence_snapshots;
CREATE POLICY pol_signing_insert ON signing.evidence_snapshots
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (true);

DROP POLICY IF EXISTS pol_reports_read ON reporting.execution_reports;
CREATE POLICY pol_reports_read ON reporting.execution_reports
FOR SELECT TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_reports_insert ON reporting.execution_reports;
CREATE POLICY pol_reports_insert ON reporting.execution_reports
FOR INSERT TO bdai_evidence_writer, bdai_api_service
WITH CHECK (true);

DROP POLICY IF EXISTS pol_retention_auditor_read_holds ON retention.legal_holds;
CREATE POLICY pol_retention_auditor_read_holds ON retention.legal_holds
FOR SELECT TO bdai_auditor, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_retention_service_write_holds ON retention.legal_holds;
CREATE POLICY pol_retention_service_write_holds ON retention.legal_holds
FOR ALL TO bdai_api_service
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS pol_retention_auditor_read_queue ON retention.retention_enforcement_queue;
CREATE POLICY pol_retention_auditor_read_queue ON retention.retention_enforcement_queue
FOR SELECT TO bdai_auditor, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_retention_service_write_queue ON retention.retention_enforcement_queue;
CREATE POLICY pol_retention_service_write_queue ON retention.retention_enforcement_queue
FOR ALL TO bdai_api_service
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS pol_retention_auditor_read_disposition ON retention.disposition_records;
CREATE POLICY pol_retention_auditor_read_disposition ON retention.disposition_records
FOR SELECT TO bdai_auditor, bdai_api_service
USING (true);

DROP POLICY IF EXISTS pol_retention_service_write_disposition ON retention.disposition_records;
CREATE POLICY pol_retention_service_write_disposition ON retention.disposition_records
FOR ALL TO bdai_api_service
USING (true)
WITH CHECK (true);

CREATE OR REPLACE VIEW governance_admin.rls_enabled_tables AS
SELECT n.nspname AS schema_name, c.relname AS table_name, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('evidence','archive','signing','reporting','retention')
  AND c.relkind IN ('r','p')
ORDER BY n.nspname, c.relname;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (101, '101', 'Row-level security policies', 'V101__row_level_security_policies.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
