-- ============================================================================
-- BioDiscoveryAI Regulated Compliance Health Views
-- Migration: V106__regulated_compliance_health_views.sql
-- Purpose:
--   Add database-native inspection readiness views for audit chain health,
--   signature gaps, retention gaps, RLS status, partition coverage, and
--   constraint validation state.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW evidence.finalized_runs_without_signature AS
SELECT r.run_id, r.script_id, r.module_id, r.status, r.run_state, r.finalized_at, r.finalized_by
FROM evidence.execution_runs r
LEFT JOIN evidence.electronic_signatures s
  ON s.related_entity_type = 'execution_run'
 AND s.related_entity_id = r.run_id
 AND s.signature_meaning IN ('approved','certified','validated')
WHERE r.run_state IN ('finalized','superseded','corrected')
  AND s.signature_id IS NULL;

CREATE OR REPLACE VIEW archive.artifacts_missing_retention_until AS
SELECT artifact_id, run_id, artifact_name, artifact_type, retention_period, legal_hold, archive_state, created_at
FROM archive.artifacts
WHERE retention_period NOT IN ('none','permanent')
  AND retention_until IS NULL;

CREATE OR REPLACE VIEW retention.legal_hold_active_items AS
SELECT related_entity_type, related_entity_id, COUNT(*) AS active_hold_count, MIN(placed_at) AS first_hold_at
FROM retention.legal_holds
WHERE hold_status = 'active'
GROUP BY related_entity_type, related_entity_id;

CREATE OR REPLACE VIEW evidence.ingestion_failure_summary AS
SELECT source_system,
       request_status,
       COUNT(*) AS request_count,
       MIN(received_at) AS first_seen_at,
       MAX(received_at) AS last_seen_at
FROM evidence.ingestion_requests
WHERE request_status IN ('rejected','failed')
GROUP BY source_system, request_status;

CREATE OR REPLACE VIEW governance_admin.regulated_database_readiness AS
SELECT 'constraint_validation' AS readiness_area,
       quality_gate_status AS status,
       jsonb_build_object('unvalidated_constraint_count', unvalidated_constraint_count) AS details
FROM governance_admin.database_quality_gate
UNION ALL
SELECT 'audit_chain',
       CASE WHEN COUNT(*) FILTER (WHERE chain_status <> 'PASS') = 0 THEN 'PASS' ELSE 'FAIL' END,
       jsonb_build_object('failed_runs', COUNT(*) FILTER (WHERE chain_status <> 'PASS'))
FROM evidence.audit_chain_health
UNION ALL
SELECT 'finalized_run_signatures',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       jsonb_build_object('finalized_runs_without_signature', COUNT(*))
FROM evidence.finalized_runs_without_signature
UNION ALL
SELECT 'artifact_retention',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       jsonb_build_object('artifacts_missing_retention_until', COUNT(*))
FROM archive.artifacts_missing_retention_until
UNION ALL
SELECT 'partition_coverage',
       CASE WHEN COUNT(*) FILTER (WHERE parent_exists = false OR partition_count = 0) = 0 THEN 'PASS' ELSE 'FAIL' END,
       jsonb_build_object('uncovered_partitioned_tables', COUNT(*) FILTER (WHERE parent_exists = false OR partition_count = 0))
FROM governance_admin.partition_policy_coverage
UNION ALL
SELECT 'data_dictionary',
       CASE WHEN COUNT(*) FILTER (WHERE completion_status <> 'PASS') = 0 THEN 'PASS' ELSE 'INCOMPLETE' END,
       jsonb_build_object('incomplete_areas', COUNT(*) FILTER (WHERE completion_status <> 'PASS'))
FROM governance_admin.data_dictionary_completion;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (106, '106', 'Regulated compliance health views', 'V106__regulated_compliance_health_views.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
