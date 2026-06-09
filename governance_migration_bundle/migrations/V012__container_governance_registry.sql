-- ============================================================================
-- BioDiscoveryAI Container Governance Registry
-- Migration: V011__container_governance_registry.sql
-- Purpose:
--   SQL-first container governance, package approval, image lineage,
--   Dockerfile/Apptainer generation, DevSecOps evidence, validation,
--   audit logging, and runtime traceability.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.modules (
    module_id              TEXT PRIMARY KEY,
    module_name            TEXT NOT NULL,
    module_version         TEXT NOT NULL,
    module_description     TEXT NOT NULL,
    business_purpose       TEXT NOT NULL,
    scientific_purpose     TEXT,
    compliance_scope       TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    owner                  TEXT NOT NULL,
    status                 TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'active', 'deprecated', 'retired')),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(module_id, module_version)
);

CREATE TABLE IF NOT EXISTS container_governance.scripts (
    script_id              TEXT PRIMARY KEY,
    module_id              TEXT NOT NULL REFERENCES container_governance.modules(module_id),
    script_name            TEXT NOT NULL,
    script_path            TEXT NOT NULL,
    script_version         TEXT NOT NULL,
    task_description       TEXT NOT NULL,
    task_purpose           TEXT NOT NULL,
    expected_inputs        JSONB NOT NULL DEFAULT '[]',
    expected_outputs       JSONB NOT NULL DEFAULT '[]',
    checksum_sha256        TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(module_id, script_name, script_version)
);

CREATE TABLE IF NOT EXISTS container_governance.approved_packages (
    package_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    package_manager        TEXT NOT NULL CHECK (
        package_manager IN ('apt', 'npm', 'pip', 'conda', 'system', 'binary')
    ),
    package_name           TEXT NOT NULL,
    package_version        TEXT NOT NULL,
    package_description    TEXT NOT NULL,
    inclusion_reason       TEXT NOT NULL,
    functional_role        TEXT NOT NULL,
    example_usage          TEXT,
    required_by_module     TEXT,
    required_by_script     TEXT,
    security_risk_level    TEXT NOT NULL CHECK (
        security_risk_level IN ('low', 'medium', 'high', 'critical')
    ),
    compliance_relevance   TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    license_name           TEXT,
    package_source_url     TEXT,
    package_sha256         TEXT,
    approval_status        TEXT NOT NULL DEFAULT 'pending' CHECK (
        approval_status IN ('pending', 'approved', 'rejected', 'deprecated')
    ),
    approved_by            TEXT,
    approved_at            TIMESTAMPTZ,
    approval_notes         TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(package_manager, package_name, package_version)
);

CREATE TABLE IF NOT EXISTS container_governance.base_images (
    base_image_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_name             TEXT NOT NULL,
    image_tag              TEXT NOT NULL,
    image_digest_sha256    TEXT NOT NULL,
    os_family              TEXT NOT NULL,
    os_version             TEXT NOT NULL,
    description            TEXT NOT NULL,
    inclusion_reason       TEXT NOT NULL,
    security_status        TEXT NOT NULL DEFAULT 'pending'
        CHECK (security_status IN ('pending', 'reviewed', 'approved', 'rejected')),
    approval_status        TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'deprecated')),
    approved_by            TEXT,
    approved_at            TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(image_name, image_tag, image_digest_sha256)
);

CREATE TABLE IF NOT EXISTS container_governance.container_images (
    image_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id              TEXT NOT NULL REFERENCES container_governance.modules(module_id),
    script_id              TEXT NOT NULL REFERENCES container_governance.scripts(script_id),
    base_image_id          UUID NOT NULL REFERENCES container_governance.base_images(base_image_id),
    image_name             TEXT NOT NULL,
    image_version          TEXT NOT NULL,
    dockerfile_id          TEXT NOT NULL UNIQUE,
    apptainer_def_id       TEXT UNIQUE,
    container_purpose      TEXT NOT NULL,
    container_description  TEXT NOT NULL,
    runtime_user           TEXT NOT NULL DEFAULT 'nonroot',
    network_policy         TEXT NOT NULL DEFAULT 'none',
    filesystem_policy      TEXT NOT NULL DEFAULT 'read_only',
    privilege_policy       TEXT NOT NULL DEFAULT 'no_new_privileges',
    dockerfile_sha256      TEXT,
    apptainer_def_sha256   TEXT,
    docker_image_digest    TEXT,
    apptainer_sif_sha256   TEXT,
    approval_status        TEXT NOT NULL DEFAULT 'draft' CHECK (
        approval_status IN ('draft', 'pending_review', 'approved', 'rejected', 'retired')
    ),
    validation_status      TEXT NOT NULL DEFAULT 'not_started' CHECK (
        validation_status IN ('not_started', 'iq_passed', 'oq_passed', 'pq_passed', 'validated', 'failed')
    ),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_by            TEXT,
    approved_at            TIMESTAMPTZ,
    UNIQUE(module_id, script_id, image_name, image_version)
);

CREATE TABLE IF NOT EXISTS container_governance.image_packages (
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    package_id             UUID NOT NULL REFERENCES container_governance.approved_packages(package_id),
    install_order          INT NOT NULL,
    install_scope          TEXT NOT NULL DEFAULT 'runtime',
    required               BOOLEAN NOT NULL DEFAULT true,
    why_this_image_needs_it TEXT NOT NULL,
    removal_impact          TEXT NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (image_id, package_id),
    UNIQUE(image_id, install_order)
);

CREATE TABLE IF NOT EXISTS container_governance.change_controls (
    change_control_id      TEXT PRIMARY KEY,
    image_id               UUID REFERENCES container_governance.container_images(image_id),
    module_id              TEXT REFERENCES container_governance.modules(module_id),
    change_title           TEXT NOT NULL,
    change_description     TEXT NOT NULL,
    change_reason          TEXT NOT NULL,
    risk_assessment        TEXT NOT NULL,
    impact_assessment      TEXT NOT NULL,
    rollback_plan          TEXT NOT NULL,
    requested_by           TEXT NOT NULL,
    reviewed_by            TEXT,
    approved_by            TEXT,
    status                 TEXT NOT NULL DEFAULT 'requested' CHECK (
        status IN ('requested', 'under_review', 'approved', 'rejected', 'implemented', 'closed')
    ),
    requested_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at            TIMESTAMPTZ,
    closed_at              TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.image_builds (
    build_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    change_control_id      TEXT REFERENCES container_governance.change_controls(change_control_id),
    git_repo               TEXT NOT NULL,
    git_branch             TEXT NOT NULL,
    git_commit_sha         TEXT NOT NULL,
    git_dirty              BOOLEAN NOT NULL DEFAULT false,
    build_tool             TEXT NOT NULL,
    build_host             TEXT NOT NULL,
    builder_identity       TEXT NOT NULL,
    build_started_at       TIMESTAMPTZ NOT NULL,
    build_finished_at      TIMESTAMPTZ,
    build_status           TEXT NOT NULL CHECK (
        build_status IN ('started', 'passed', 'failed', 'cancelled')
    ),
    dockerfile_sha256      TEXT,
    docker_image_digest    TEXT,
    apptainer_sif_sha256   TEXT,
    build_log_uri          TEXT,
    build_log_sha256       TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.container_evidence (
    evidence_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    build_id               UUID REFERENCES container_governance.image_builds(build_id),
    evidence_type          TEXT NOT NULL CHECK (
        evidence_type IN (
            'sbom',
            'vulnerability_scan',
            'license_scan',
            'secret_scan',
            'signature',
            'provenance',
            'attestation',
            'policy_check',
            'iq',
            'oq',
            'pq',
            'risk_assessment',
            'approval_record'
        )
    ),
    evidence_tool          TEXT NOT NULL,
    evidence_uri           TEXT NOT NULL,
    evidence_sha256        TEXT NOT NULL,
    evidence_summary       JSONB NOT NULL DEFAULT '{}',
    pass_fail_status       TEXT NOT NULL CHECK (
        pass_fail_status IN ('pass', 'fail', 'warning', 'accepted_risk')
    ),
    generated_by           TEXT NOT NULL,
    generated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.validation_records (
    validation_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    validation_type        TEXT NOT NULL CHECK (validation_type IN ('IQ', 'OQ', 'PQ')),
    test_name              TEXT NOT NULL,
    test_description       TEXT NOT NULL,
    expected_result        TEXT NOT NULL,
    actual_result          TEXT NOT NULL,
    status                 TEXT NOT NULL CHECK (
        status IN ('pass', 'fail', 'not_run', 'blocked')
    ),
    executed_by            TEXT NOT NULL,
    executed_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri           TEXT,
    evidence_sha256        TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.execution_runs (
    execution_run_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    build_id               UUID REFERENCES container_governance.image_builds(build_id),
    module_id              TEXT NOT NULL REFERENCES container_governance.modules(module_id),
    script_id              TEXT NOT NULL REFERENCES container_governance.scripts(script_id),
    workflow_engine        TEXT NOT NULL,
    scheduler_type         TEXT NOT NULL,
    execution_environment  TEXT NOT NULL,
    container_runtime      TEXT NOT NULL CHECK (
        container_runtime IN ('docker', 'apptainer', 'singularity', 'none')
    ),
    runtime_image_digest   TEXT,
    runtime_sif_sha256     TEXT,
    command_executed       TEXT NOT NULL,
    parameters             JSONB NOT NULL DEFAULT '{}',
    input_artifacts        JSONB NOT NULL DEFAULT '[]',
    output_artifacts       JSONB NOT NULL DEFAULT '[]',
    run_started_at         TIMESTAMPTZ NOT NULL,
    run_finished_at        TIMESTAMPTZ,
    run_status             TEXT NOT NULL CHECK (
        run_status IN ('started', 'passed', 'failed', 'cancelled')
    ),
    exit_code              INT,
    stdout_uri             TEXT,
    stderr_uri             TEXT,
    runtime_log_uri        TEXT,
    runtime_log_sha256     TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.audit_events (
    audit_event_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_time             TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor                  TEXT NOT NULL,
    action                 TEXT NOT NULL,
    entity_type            TEXT NOT NULL,
    entity_id              TEXT NOT NULL,
    event_description      TEXT NOT NULL,
    before_state           JSONB,
    after_state            JSONB,
    source_ip              TEXT,
    user_agent             TEXT,
    request_id             TEXT,
    previous_event_hash    TEXT,
    event_hash             TEXT NOT NULL DEFAULT 'pending',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.governance_decisions (
    decision_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type    TEXT NOT NULL,
    related_entity_id      TEXT NOT NULL,
    decision_type          TEXT NOT NULL CHECK (
        decision_type IN (
            'package_approval',
            'image_approval',
            'risk_acceptance',
            'validation_acceptance',
            'deployment_approval',
            'deprecation'
        )
    ),
    decision_summary       TEXT NOT NULL,
    decision_rationale     TEXT NOT NULL,
    decision_status        TEXT NOT NULL CHECK (
        decision_status IN ('approved', 'rejected', 'deferred')
    ),
    decided_by             TEXT NOT NULL,
    decided_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    effective_until        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_container_images_module_id
ON container_governance.container_images(module_id);

CREATE INDEX IF NOT EXISTS idx_container_images_script_id
ON container_governance.container_images(script_id);

CREATE INDEX IF NOT EXISTS idx_image_packages_image_id
ON container_governance.image_packages(image_id);

CREATE INDEX IF NOT EXISTS idx_image_builds_image_id
ON container_governance.image_builds(image_id);

CREATE INDEX IF NOT EXISTS idx_container_evidence_image_id
ON container_governance.container_evidence(image_id);

CREATE INDEX IF NOT EXISTS idx_execution_runs_image_id
ON container_governance.execution_runs(image_id);

CREATE INDEX IF NOT EXISTS idx_execution_runs_module_id
ON container_governance.execution_runs(module_id);

CREATE INDEX IF NOT EXISTS idx_audit_events_entity
ON container_governance.audit_events(entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_audit_events_time
ON container_governance.audit_events(event_time);

CREATE OR REPLACE VIEW container_governance.v_container_full_lineage AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.dockerfile_id,
    ci.apptainer_def_id,
    m.module_id,
    m.module_name,
    m.module_version,
    s.script_id,
    s.script_name,
    s.script_path,
    bi.image_name AS base_image_name,
    bi.image_tag AS base_image_tag,
    bi.image_digest_sha256 AS base_image_digest,
    ci.docker_image_digest,
    ci.apptainer_sif_sha256,
    ci.approval_status,
    ci.validation_status,
    cc.change_control_id,
    cc.status AS change_control_status,
    ib.build_id,
    ib.git_commit_sha,
    ib.build_status,
    ib.build_started_at,
    ib.build_finished_at
FROM container_governance.container_images ci
JOIN container_governance.modules m
    ON ci.module_id = m.module_id
JOIN container_governance.scripts s
    ON ci.script_id = s.script_id
JOIN container_governance.base_images bi
    ON ci.base_image_id = bi.base_image_id
LEFT JOIN container_governance.change_controls cc
    ON cc.image_id = ci.image_id
LEFT JOIN container_governance.image_builds ib
    ON ib.image_id = ci.image_id;

CREATE OR REPLACE VIEW container_governance.v_image_package_justification AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.module_id,
    ci.script_id,
    ap.package_manager,
    ap.package_name,
    ap.package_version,
    ap.package_description,
    ap.inclusion_reason,
    ap.functional_role,
    ap.security_risk_level,
    ap.license_name,
    ap.approval_status,
    ip.install_order,
    ip.why_this_image_needs_it,
    ip.removal_impact
FROM container_governance.container_images ci
JOIN container_governance.image_packages ip
    ON ci.image_id = ip.image_id
JOIN container_governance.approved_packages ap
    ON ip.package_id = ap.package_id
ORDER BY ci.image_name, ip.install_order;

CREATE OR REPLACE VIEW container_governance.v_container_deployment_readiness AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.module_id,
    ci.script_id,
    ci.approval_status,
    ci.validation_status,
    COUNT(DISTINCT ce.evidence_type) FILTER (
        WHERE ce.pass_fail_status IN ('pass', 'accepted_risk')
    ) AS evidence_count,
    BOOL_OR(ce.evidence_type = 'sbom' AND ce.pass_fail_status = 'pass') AS has_sbom,
    BOOL_OR(ce.evidence_type = 'vulnerability_scan' AND ce.pass_fail_status IN ('pass', 'accepted_risk')) AS has_vuln_scan,
    BOOL_OR(ce.evidence_type = 'signature' AND ce.pass_fail_status = 'pass') AS has_signature,
    BOOL_OR(ce.evidence_type = 'provenance' AND ce.pass_fail_status = 'pass') AS has_provenance,
    BOOL_OR(ce.evidence_type = 'iq' AND ce.pass_fail_status = 'pass') AS has_iq,
    BOOL_OR(ce.evidence_type = 'oq' AND ce.pass_fail_status = 'pass') AS has_oq,
    BOOL_OR(ce.evidence_type = 'pq' AND ce.pass_fail_status = 'pass') AS has_pq,
    CASE
        WHEN ci.approval_status = 'approved'
         AND ci.validation_status = 'validated'
         AND BOOL_OR(ce.evidence_type = 'sbom' AND ce.pass_fail_status = 'pass')
         AND BOOL_OR(ce.evidence_type = 'vulnerability_scan' AND ce.pass_fail_status IN ('pass', 'accepted_risk'))
         AND BOOL_OR(ce.evidence_type = 'signature' AND ce.pass_fail_status = 'pass')
         AND BOOL_OR(ce.evidence_type = 'provenance' AND ce.pass_fail_status = 'pass')
        THEN 'ready'
        ELSE 'not_ready'
    END AS deployment_readiness
FROM container_governance.container_images ci
LEFT JOIN container_governance.container_evidence ce
    ON ci.image_id = ce.image_id
GROUP BY
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.module_id,
    ci.script_id,
    ci.approval_status,
    ci.validation_status;

COMMIT;
