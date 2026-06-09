-- ============================================================================
-- BioDiscoveryAI Container Governance Policy-as-Code
-- Migration: V021__container_governance_policy_as_code.sql
-- Purpose:
--   Register, version, evaluate, enforce, and audit external policy-as-code
--   controls for Dockerfiles, Apptainer definitions, container images, runtime
--   settings, registries, SBOMs, signatures, provenance, secrets, and releases.
-- Dependencies:
--   V011 + V015 + V016 + V017 + V018 + V019 + V020
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Policy Engines
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.policy_engines (
    policy_engine_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engine_name                TEXT NOT NULL UNIQUE,
    engine_type                TEXT NOT NULL CHECK (
        engine_type IN ('opa', 'conftest', 'kyverno', 'cosign_policy', 'custom_sql', 'custom_cli')
    ),
    engine_version             TEXT NOT NULL,
    engine_description         TEXT NOT NULL,
    owner                      TEXT NOT NULL,
    approval_status            TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by                TEXT,
    approved_at                TIMESTAMPTZ,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Policy Bundles
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.policy_bundles (
    policy_bundle_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_engine_id           UUID NOT NULL REFERENCES container_governance.policy_engines(policy_engine_id),

    bundle_name                TEXT NOT NULL,
    bundle_version             TEXT NOT NULL,
    bundle_description         TEXT NOT NULL,

    source_repo                TEXT NOT NULL,
    source_path                TEXT NOT NULL,
    git_commit_sha             TEXT NOT NULL,
    artifact_uri               TEXT NOT NULL,
    artifact_sha256            TEXT NOT NULL,

    policy_scope               TEXT NOT NULL CHECK (
        policy_scope IN (
            'dockerfile',
            'apptainer_definition',
            'image',
            'runtime',
            'registry',
            'sbom',
            'signature',
            'provenance',
            'release',
            'all'
        )
    ),

    enforcement_mode            TEXT NOT NULL DEFAULT 'blocking'
        CHECK (enforcement_mode IN ('advisory', 'blocking', 'monitor_only')),

    approval_status             TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),

    approved_by                 TEXT,
    approved_at                 TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(bundle_name, bundle_version)
);

-- ============================================================================
-- 3. Individual Policy Rules
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.policy_rules (
    policy_rule_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_bundle_id           UUID NOT NULL REFERENCES container_governance.policy_bundles(policy_bundle_id),

    rule_id                    TEXT NOT NULL,
    rule_name                  TEXT NOT NULL,
    rule_description           TEXT NOT NULL,

    severity                   TEXT NOT NULL CHECK (severity IN ('info', 'low', 'medium', 'high', 'critical')),
    control_objective          TEXT NOT NULL,
    remediation_guidance       TEXT NOT NULL,

    applies_to                 TEXT NOT NULL CHECK (
        applies_to IN (
            'dockerfile',
            'apptainer_definition',
            'image_metadata',
            'package_catalog',
            'runtime_policy',
            'registry_publication',
            'release_certification',
            'execution_run'
        )
    ),

    enabled                    BOOLEAN NOT NULL DEFAULT true,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(policy_bundle_id, rule_id)
);

-- ============================================================================
-- 4. Policy Evaluation Runs
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.policy_evaluation_runs (
    policy_evaluation_run_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    policy_bundle_id           UUID NOT NULL REFERENCES container_governance.policy_bundles(policy_bundle_id),
    related_entity_type        TEXT NOT NULL,
    related_entity_id          TEXT NOT NULL,

    image_id                   UUID REFERENCES container_governance.container_images(image_id),
    build_id                   UUID REFERENCES container_governance.image_builds(build_id),

    evaluation_tool            TEXT NOT NULL,
    evaluation_tool_version    TEXT NOT NULL,
    command_executed           TEXT NOT NULL,

    started_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at                TIMESTAMPTZ,
    status                     TEXT NOT NULL DEFAULT 'started'
        CHECK (status IN ('started', 'passed', 'failed', 'warning', 'cancelled')),

    raw_report_uri             TEXT,
    raw_report_sha256          TEXT,
    summary                    JSONB NOT NULL DEFAULT '{}',

    evaluated_by               TEXT NOT NULL
);

-- ============================================================================
-- 5. Policy Rule Results
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.policy_rule_results (
    policy_rule_result_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    policy_evaluation_run_id   UUID NOT NULL
        REFERENCES container_governance.policy_evaluation_runs(policy_evaluation_run_id),

    policy_rule_id             UUID REFERENCES container_governance.policy_rules(policy_rule_id),
    rule_id                    TEXT NOT NULL,
    rule_name                  TEXT NOT NULL,

    result_status              TEXT NOT NULL CHECK (
        result_status IN ('pass', 'fail', 'warning', 'not_applicable', 'accepted_risk')
    ),

    severity                   TEXT NOT NULL CHECK (severity IN ('info', 'low', 'medium', 'high', 'critical')),
    finding_summary            TEXT NOT NULL,
    finding_detail             TEXT,
    remediation_guidance       TEXT,

    waiver_id                  UUID,
    evidence_uri               TEXT,
    evidence_sha256            TEXT,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 6. Policy Enforcement Function
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.has_blocking_policy_failures(p_image_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.policy_evaluation_runs per
        JOIN container_governance.policy_bundles pb
            ON pb.policy_bundle_id = per.policy_bundle_id
        JOIN container_governance.policy_rule_results prr
            ON prr.policy_evaluation_run_id = per.policy_evaluation_run_id
        WHERE per.image_id = p_image_id
          AND pb.enforcement_mode = 'blocking'
          AND prr.result_status = 'fail'
          AND prr.severity IN ('high', 'critical')
          AND NOT EXISTS (
              SELECT 1
              FROM container_governance.exception_waivers ew
              WHERE ew.waiver_id = prr.waiver_id
                AND ew.status = 'active'
                AND ew.expires_on >= CURRENT_DATE
          )
    )
    INTO result;

    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION container_governance.prevent_execution_with_blocking_policy_failures()
RETURNS TRIGGER AS $$
BEGIN
    IF container_governance.has_blocking_policy_failures(NEW.image_id) THEN
        RAISE EXCEPTION
            'Image % has unresolved blocking policy-as-code failures.',
            NEW.image_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_policy_failed_execution
ON container_governance.execution_runs;

CREATE TRIGGER trg_prevent_policy_failed_execution
BEFORE INSERT ON container_governance.execution_runs
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_execution_with_blocking_policy_failures();

-- ============================================================================
-- 7. Views
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_policy_as_code_status AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.module_id,
    ci.script_id,
    COUNT(prr.policy_rule_result_id) AS total_policy_results,
    COUNT(prr.policy_rule_result_id) FILTER (WHERE prr.result_status = 'pass') AS passed_rules,
    COUNT(prr.policy_rule_result_id) FILTER (WHERE prr.result_status = 'fail') AS failed_rules,
    COUNT(prr.policy_rule_result_id) FILTER (
        WHERE prr.result_status = 'fail'
          AND prr.severity IN ('high', 'critical')
    ) AS blocking_failures,
    container_governance.has_blocking_policy_failures(ci.image_id) AS has_blocking_policy_failures
FROM container_governance.container_images ci
LEFT JOIN container_governance.policy_evaluation_runs per
    ON per.image_id = ci.image_id
LEFT JOIN container_governance.policy_rule_results prr
    ON prr.policy_evaluation_run_id = per.policy_evaluation_run_id
GROUP BY ci.image_id, ci.image_name, ci.image_version, ci.module_id, ci.script_id;

-- ============================================================================
-- 8. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_policy_bundles_engine
ON container_governance.policy_bundles(policy_engine_id);

CREATE INDEX IF NOT EXISTS idx_policy_rules_bundle
ON container_governance.policy_rules(policy_bundle_id);

CREATE INDEX IF NOT EXISTS idx_policy_evaluation_runs_image
ON container_governance.policy_evaluation_runs(image_id);

CREATE INDEX IF NOT EXISTS idx_policy_rule_results_run
ON container_governance.policy_rule_results(policy_evaluation_run_id);

-- ============================================================================
-- 9. Seed Standard Policy Engines
-- ============================================================================

INSERT INTO container_governance.policy_engines (
    engine_name,
    engine_type,
    engine_version,
    engine_description,
    owner,
    approval_status,
    approved_by,
    approved_at
)
VALUES
(
    'opa-conftest-container-policy',
    'conftest',
    'TO_BE_CAPTURED',
    'OPA/Conftest policy engine for Dockerfile, Apptainer, image metadata, and runtime-policy validation.',
    'BioDiscoveryAI Security Engineering',
    'approved',
    'Architecture Review Board',
    now()
),
(
    'postgresql-container-policy-gates',
    'custom_sql',
    '1.0.0',
    'SQL-native policy gates enforcing deployability, release certification, vulnerability, license, signature, and provenance requirements.',
    'BioDiscoveryAI Platform Engineering',
    'approved',
    'Architecture Review Board',
    now()
)
ON CONFLICT (engine_name) DO NOTHING;

COMMIT;
