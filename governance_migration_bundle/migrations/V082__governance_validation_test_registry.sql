-- ============================================================================
-- BioDiscoveryAI Governance Validation Test Registry
-- Migration: V088__governance_validation_test_registry.sql
-- Purpose:
--   Register validation tests for migrations, schemas, data contracts,
--   generators, API contracts, CLI contracts, policy gates, release readiness,
--   and audit evidence completeness.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_contracts;

CREATE TABLE IF NOT EXISTS governance_contracts.validation_suites (
    validation_suite_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    suite_code TEXT NOT NULL UNIQUE,
    suite_name TEXT NOT NULL,
    suite_description TEXT NOT NULL,
    suite_type TEXT NOT NULL CHECK (
        suite_type IN ('migration','schema','data_contract','api','cli','generator','policy','release','audit','performance','security','other')
    ),
    owner TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.validation_tests (
    validation_test_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    validation_suite_id UUID NOT NULL REFERENCES governance_contracts.validation_suites(validation_suite_id),
    test_code TEXT NOT NULL,
    test_name TEXT NOT NULL,
    test_description TEXT NOT NULL,
    test_method TEXT NOT NULL CHECK (
        test_method IN ('sql_query','plpgsql_function','external_cli','api_call','manual_review','sampling','integration_test')
    ),
    test_query TEXT,
    expected_result TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'high'
        CHECK (severity IN ('low','medium','high','critical')),
    blocking BOOLEAN NOT NULL DEFAULT true,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(validation_suite_id, test_code)
);

CREATE TABLE IF NOT EXISTS governance_contracts.validation_test_runs (
    validation_test_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    validation_suite_id UUID NOT NULL REFERENCES governance_contracts.validation_suites(validation_suite_id),
    run_name TEXT NOT NULL,
    run_environment TEXT NOT NULL,
    git_commit_sha TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    run_status TEXT NOT NULL DEFAULT 'started'
        CHECK (run_status IN ('started','passed','failed','warning','cancelled')),
    executed_by TEXT NOT NULL,
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_contracts.validation_test_results (
    validation_test_result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    validation_test_run_id UUID NOT NULL REFERENCES governance_contracts.validation_test_runs(validation_test_run_id),
    validation_test_id UUID NOT NULL REFERENCES governance_contracts.validation_tests(validation_test_id),
    result_status TEXT NOT NULL CHECK (result_status IN ('pass','fail','warning','not_applicable')),
    actual_result TEXT NOT NULL,
    error_message TEXT,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW governance_contracts.v_validation_readiness AS
SELECT
    vs.suite_code,
    vs.suite_name,
    vs.suite_type,
    vtr.run_name,
    vtr.run_status,
    COUNT(vt.validation_test_id) AS total_tests,
    COUNT(vres.validation_test_result_id) FILTER (WHERE vres.result_status = 'pass') AS passed_tests,
    COUNT(vres.validation_test_result_id) FILTER (WHERE vres.result_status = 'fail') AS failed_tests,
    COUNT(vres.validation_test_result_id) FILTER (WHERE vres.result_status = 'fail' AND vt.blocking = true) AS blocking_failed_tests
FROM governance_contracts.validation_suites vs
LEFT JOIN governance_contracts.validation_tests vt ON vt.validation_suite_id = vs.validation_suite_id
LEFT JOIN governance_contracts.validation_test_runs vtr ON vtr.validation_suite_id = vs.validation_suite_id
LEFT JOIN governance_contracts.validation_test_results vres
    ON vres.validation_test_run_id = vtr.validation_test_run_id
   AND vres.validation_test_id = vt.validation_test_id
GROUP BY vs.suite_code, vs.suite_name, vs.suite_type, vtr.run_name, vtr.run_status;

INSERT INTO governance_contracts.validation_suites (
    suite_code, suite_name, suite_description, suite_type, owner
)
VALUES
('MIGRATION_VALIDATION','Migration Validation Suite','Validates that all governance migrations run cleanly and create expected objects.','migration','Platform Engineering'),
('RELEASE_READINESS_VALIDATION','Release Readiness Validation Suite','Validates release readiness, evidence completeness, signatures, provenance, policy gates, and validation records.','release','Compliance Engineering'),
('GENERATOR_VALIDATION','Generator Validation Suite','Validates deterministic generation and artifact hash consistency.','generator','Platform Engineering')
ON CONFLICT (suite_code) DO NOTHING;

COMMIT;
