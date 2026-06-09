-- ============================================================================
-- BioDiscoveryAI Constraint Validation and Data Quality Gate
-- Migration: V100__constraint_validation_and_data_quality_gate.sql
-- Purpose:
--   Validate hardening constraints introduced as NOT VALID and expose database
--   data-quality state for regulated release checks.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT conrelid::regclass AS table_name, conname
        FROM pg_constraint
        WHERE convalidated = false
          AND connamespace IN (
              'evidence'::regnamespace,
              'archive'::regnamespace,
              'registry'::regnamespace,
              'signing'::regnamespace
          )
        ORDER BY conrelid::regclass::text, conname
    LOOP
        EXECUTE format('ALTER TABLE %s VALIDATE CONSTRAINT %I', r.table_name, r.conname);
    END LOOP;
END $$;

CREATE OR REPLACE VIEW governance_admin.constraint_validation_status AS
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    con.convalidated AS validated
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('registry','evidence','archive','reporting','signing','retention','governance_admin')
ORDER BY n.nspname, c.relname, con.conname;

CREATE OR REPLACE VIEW governance_admin.unvalidated_constraints AS
SELECT *
FROM governance_admin.constraint_validation_status
WHERE validated = false;

CREATE OR REPLACE VIEW governance_admin.database_quality_gate AS
SELECT
    now() AS checked_at,
    COUNT(*) FILTER (WHERE validated = false) AS unvalidated_constraint_count,
    CASE WHEN COUNT(*) FILTER (WHERE validated = false) = 0 THEN 'PASS' ELSE 'FAIL' END AS quality_gate_status
FROM governance_admin.constraint_validation_status;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (100, '100', 'Constraint validation and data quality gate', 'V100__constraint_validation_and_data_quality_gate.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
