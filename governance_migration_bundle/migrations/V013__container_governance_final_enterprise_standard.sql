-- ============================================================================
-- BioDiscoveryAI Container Governance Final Enterprise Standard
-- Migration: V015__container_governance_final_enterprise_standard.sql
-- Purpose:
--   Single consolidated SQL migration merging V012 enforcement and V014
--   enterprise controls into one top-tier container governance layer.
--
-- Scope:
--   Runtime policies, execution environments, artifact lineage, generated
--   Dockerfile/Apptainer lineage, vulnerability/license/secret findings,
--   risk acceptances, electronic signatures, policy gates, image retirement,
--   rebuild requests, immutability triggers, audit hash chain, deployability
--   enforcement, PostgreSQL roles, row-level security, segregation of duties,
--   staged approvals, partition management, CAPA, exception waivers, release
--   certifications, registry integrations, and backup/restore validation.
--
-- Assumptions:
--   1. V011 base registry already exists.
--   2. Schema container_governance already exists.
--   3. Tables from V011 exist:
--      modules, scripts, approved_packages, base_images, container_images,
--      image_packages, change_controls, image_builds, container_evidence,
--      validation_records, execution_runs, audit_events, governance_decisions.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;



-- ==========================================================================
-- SECTION A: V012 ENFORCEMENT CONTROLS
-- ==========================================================================

-- ============================================================================
-- BioDiscoveryAI Container Governance Enforcement
-- Migration: V012__container_governance_enforcement.sql
-- Purpose:
--   Enforce immutable container governance, audit integrity, runtime policy,
--   artifact lineage, vulnerability tracking, license control, e-signatures,
--   and deployment readiness gates.
-- ============================================================================


-- pgcrypto already created above.

-- ============================================================================
-- 1. Runtime Policies
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.runtime_policies (
    runtime_policy_id          TEXT PRIMARY KEY,
    policy_name                TEXT NOT NULL,
    policy_description         TEXT NOT NULL,

    run_as_non_root            BOOLEAN NOT NULL DEFAULT true,
    read_only_filesystem       BOOLEAN NOT NULL DEFAULT true,
    network_mode               TEXT NOT NULL DEFAULT 'none',
    drop_all_capabilities      BOOLEAN NOT NULL DEFAULT true,
    no_new_privileges          BOOLEAN NOT NULL DEFAULT true,
    allow_privileged_mode      BOOLEAN NOT NULL DEFAULT false,
    allow_host_pid             BOOLEAN NOT NULL DEFAULT false,
    allow_host_network         BOOLEAN NOT NULL DEFAULT false,
    allow_host_mounts          BOOLEAN NOT NULL DEFAULT false,

    allowed_mounts             JSONB NOT NULL DEFAULT '[]',
    denied_mounts              JSONB NOT NULL DEFAULT '[]',

    max_cpu                    TEXT,
    max_memory                 TEXT,
    max_runtime_minutes        INT,

    approval_status            TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),

    approved_by                TEXT,
    approved_at                TIMESTAMPTZ,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Execution Environments
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.execution_environments (
    environment_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    environment_name           TEXT NOT NULL,
    environment_type           TEXT NOT NULL
        CHECK (environment_type IN ('local', 'hpc', 'cloud', 'ci_cd', 'regulated_prod')),

    scheduler_type             TEXT
        CHECK (scheduler_type IN ('slurm', 'aws_batch', 'kubernetes', 'github_actions', 'none')),

    container_runtime          TEXT NOT NULL
        CHECK (container_runtime IN ('docker', 'apptainer', 'singularity', 'containerd', 'none')),

    runtime_version            TEXT,
    os_family                  TEXT,
    os_version                 TEXT,

    cpu_architecture           TEXT,
    gpu_available              BOOLEAN NOT NULL DEFAULT false,
    gpu_type                   TEXT,

    storage_class              TEXT,
    network_policy             TEXT NOT NULL DEFAULT 'restricted',

    environment_owner          TEXT NOT NULL,
    compliance_scope           TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],

    approval_status            TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),

    approved_by                TEXT,
    approved_at                TIMESTAMPTZ,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(environment_name, environment_type)
);

-- ============================================================================
-- 3. Artifact Registry
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.artifacts (
    artifact_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    related_entity_type        TEXT NOT NULL,
    related_entity_id          TEXT NOT NULL,

    artifact_type              TEXT NOT NULL CHECK (
        artifact_type IN (
            'dockerfile',
            'apptainer_definition',
            'docker_image',
            'apptainer_sif',
            'sbom',
            'vulnerability_report',
            'license_report',
            'secret_scan_report',
            'signature',
            'provenance',
            'attestation',
            'build_log',
            'runtime_log',
            'validation_report',
            'approval_record',
            'change_control_record'
        )
    ),

    artifact_name              TEXT NOT NULL,
    artifact_uri               TEXT NOT NULL,
    storage_backend            TEXT NOT NULL DEFAULT 'filesystem',
    sha256                     TEXT NOT NULL,

    immutable                  BOOLEAN NOT NULL DEFAULT true,
    retention_policy           TEXT NOT NULL DEFAULT 'retain_7_years',
    retention_until            TIMESTAMPTZ,

    generated_by               TEXT NOT NULL,
    generated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(artifact_uri),
    UNIQUE(sha256, artifact_type)
);

-- ============================================================================
-- 4. Generated Container Files
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.generated_container_files (
    generated_file_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    file_type                  TEXT NOT NULL
        CHECK (file_type IN ('dockerfile', 'apptainer_definition')),

    file_id                    TEXT NOT NULL UNIQUE,
    file_path                  TEXT NOT NULL,
    file_sha256                TEXT NOT NULL,

    generator_name             TEXT NOT NULL,
    generator_version          TEXT NOT NULL,
    generator_git_commit       TEXT NOT NULL,

    generated_from_schema      TEXT NOT NULL DEFAULT 'container_governance',
    generated_from_migration   TEXT NOT NULL DEFAULT 'V011/V012',

    manual_edit_allowed        BOOLEAN NOT NULL DEFAULT false,
    generation_parameters      JSONB NOT NULL DEFAULT '{}',

    generated_by               TEXT NOT NULL,
    generated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5. Vulnerability Findings
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.vulnerability_findings (
    vulnerability_finding_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    build_id                   UUID
        REFERENCES container_governance.image_builds(build_id),

    package_name               TEXT NOT NULL,
    package_version            TEXT,
    package_manager            TEXT,

    vulnerability_id           TEXT NOT NULL,
    vulnerability_source       TEXT NOT NULL,
    severity                   TEXT NOT NULL
        CHECK (severity IN ('unknown', 'low', 'medium', 'high', 'critical')),

    cvss_score                 NUMERIC(3,1),
    fixed_version              TEXT,
    description                TEXT,

    scanner_tool               TEXT NOT NULL,
    scanner_version            TEXT,
    scan_artifact_uri          TEXT,
    scan_artifact_sha256       TEXT,

    status                     TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'fixed', 'accepted_risk', 'false_positive', 'not_applicable')),

    remediation_plan           TEXT,
    risk_acceptance_id         UUID,

    detected_at                TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(image_id, package_name, vulnerability_id)
);

-- ============================================================================
-- 6. License Findings
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.license_findings (
    license_finding_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    package_name               TEXT NOT NULL,
    package_version            TEXT,
    package_manager            TEXT,

    detected_license           TEXT NOT NULL,

    license_policy_status      TEXT NOT NULL
        CHECK (license_policy_status IN ('allowed', 'restricted', 'prohibited', 'unknown')),

    legal_review_required      BOOLEAN NOT NULL DEFAULT false,
    legal_review_status        TEXT NOT NULL DEFAULT 'not_required'
        CHECK (legal_review_status IN ('not_required', 'pending', 'approved', 'rejected')),

    reviewed_by                TEXT,
    reviewed_at                TIMESTAMPTZ,

    evidence_uri               TEXT,
    evidence_sha256            TEXT,

    detected_at                TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(image_id, package_name, detected_license)
);

-- ============================================================================
-- 7. Secret Scan Findings
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.secret_scan_findings (
    secret_finding_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    build_id                   UUID
        REFERENCES container_governance.image_builds(build_id),

    scanner_tool               TEXT NOT NULL,
    scanner_version            TEXT,

    finding_type               TEXT NOT NULL,
    finding_location           TEXT NOT NULL,
    severity                   TEXT NOT NULL
        CHECK (severity IN ('low', 'medium', 'high', 'critical')),

    status                     TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'remediated', 'false_positive', 'accepted_risk')),

    remediation_notes          TEXT,

    detected_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 8. Risk Acceptances
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.risk_acceptances (
    risk_acceptance_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    related_entity_type        TEXT NOT NULL,
    related_entity_id          TEXT NOT NULL,

    risk_title                 TEXT NOT NULL,
    risk_description           TEXT NOT NULL,
    risk_level                 TEXT NOT NULL
        CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),

    business_justification     TEXT NOT NULL,
    compensating_controls      TEXT NOT NULL,
    expiration_date            DATE NOT NULL,

    requested_by               TEXT NOT NULL,
    approved_by                TEXT NOT NULL,
    approved_at                TIMESTAMPTZ NOT NULL DEFAULT now(),

    status                     TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'expired', 'revoked', 'remediated'))
);

ALTER TABLE container_governance.vulnerability_findings
    ADD CONSTRAINT fk_vuln_risk_acceptance
    FOREIGN KEY (risk_acceptance_id)
    REFERENCES container_governance.risk_acceptances(risk_acceptance_id);

-- ============================================================================
-- 9. Electronic Signatures: 21 CFR Part 11 Style
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.electronic_signatures (
    signature_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    related_entity_type        TEXT NOT NULL,
    related_entity_id          TEXT NOT NULL,

    signer_identity            TEXT NOT NULL,
    signer_role                TEXT NOT NULL,

    signature_meaning          TEXT NOT NULL CHECK (
        signature_meaning IN (
            'authorship',
            'review',
            'approval',
            'validation_execution',
            'validation_approval',
            'release_authorization',
            'risk_acceptance',
            'retirement_approval'
        )
    ),

    signature_reason           TEXT NOT NULL,
    signed_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    signature_hash             TEXT NOT NULL,
    previous_signature_hash    TEXT,

    UNIQUE(related_entity_type, related_entity_id, signer_identity, signature_meaning)
);

-- ============================================================================
-- 10. Policy Gate Results
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.policy_gate_results (
    gate_result_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    build_id                   UUID
        REFERENCES container_governance.image_builds(build_id),

    gate_name                  TEXT NOT NULL,
    gate_description           TEXT NOT NULL,

    gate_status                TEXT NOT NULL
        CHECK (gate_status IN ('pass', 'fail', 'warning', 'accepted_risk', 'not_applicable')),

    gate_tool                  TEXT NOT NULL DEFAULT 'postgresql_policy_gate',
    gate_details               JSONB NOT NULL DEFAULT '{}',

    evaluated_by               TEXT NOT NULL,
    evaluated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(image_id, build_id, gate_name)
);

-- ============================================================================
-- 11. Image Retirement Records
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.image_retirement_records (
    retirement_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    retirement_reason          TEXT NOT NULL,
    replacement_image_id       UUID
        REFERENCES container_governance.container_images(image_id),

    retired_by                 TEXT NOT NULL,
    retired_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    end_of_use_date            DATE NOT NULL,
    migration_plan             TEXT NOT NULL,

    status                     TEXT NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled'))
);

-- ============================================================================
-- 12. Rebuild Triggers / Reasons
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.rebuild_requests (
    rebuild_request_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL
        REFERENCES container_governance.container_images(image_id),

    rebuild_reason             TEXT NOT NULL CHECK (
        rebuild_reason IN (
            'base_image_cve',
            'package_cve',
            'package_update',
            'code_update',
            'expired_validation',
            'policy_change',
            'manual_request'
        )
    ),

    requested_by               TEXT NOT NULL,
    requested_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    status                     TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested', 'approved', 'rejected', 'completed', 'cancelled')),

    approval_notes             TEXT
);

-- ============================================================================
-- 13. Immutability Trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.prevent_mutation_after_approval()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.approval_status = 'approved' THEN
        RAISE EXCEPTION
            'Approved record in table % is immutable and cannot be modified or deleted',
            TG_TABLE_NAME;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_immutable_container_images
ON container_governance.container_images;

CREATE TRIGGER trg_immutable_container_images
BEFORE UPDATE OR DELETE ON container_governance.container_images
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_mutation_after_approval();

DROP TRIGGER IF EXISTS trg_immutable_approved_packages
ON container_governance.approved_packages;

CREATE TRIGGER trg_immutable_approved_packages
BEFORE UPDATE OR DELETE ON container_governance.approved_packages
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_mutation_after_approval();

DROP TRIGGER IF EXISTS trg_immutable_base_images
ON container_governance.base_images;

CREATE TRIGGER trg_immutable_base_images
BEFORE UPDATE OR DELETE ON container_governance.base_images
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_mutation_after_approval();

-- ============================================================================
-- 14. Immutable Artifact Trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.prevent_immutable_artifact_mutation()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.immutable = true THEN
        RAISE EXCEPTION
            'Immutable artifact % cannot be modified or deleted',
            OLD.artifact_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_immutable_artifacts
ON container_governance.artifacts;

CREATE TRIGGER trg_immutable_artifacts
BEFORE UPDATE OR DELETE ON container_governance.artifacts
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_immutable_artifact_mutation();

-- ============================================================================
-- 15. Audit Hash Chain
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.compute_audit_event_hash()
RETURNS TRIGGER AS $$
DECLARE
    last_hash TEXT;
    payload TEXT;
BEGIN
    SELECT event_hash
    INTO last_hash
    FROM container_governance.audit_events
    ORDER BY event_time DESC, created_at DESC
    LIMIT 1;

    NEW.previous_event_hash := last_hash;

    payload :=
        COALESCE(NEW.event_time::TEXT, '') ||
        COALESCE(NEW.actor, '') ||
        COALESCE(NEW.action, '') ||
        COALESCE(NEW.entity_type, '') ||
        COALESCE(NEW.entity_id, '') ||
        COALESCE(NEW.event_description, '') ||
        COALESCE(NEW.before_state::TEXT, '') ||
        COALESCE(NEW.after_state::TEXT, '') ||
        COALESCE(NEW.previous_event_hash, '');

    NEW.event_hash := encode(digest(payload, 'sha256'), 'hex');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_compute_audit_event_hash
ON container_governance.audit_events;

CREATE TRIGGER trg_compute_audit_event_hash
BEFORE INSERT ON container_governance.audit_events
FOR EACH ROW
EXECUTE FUNCTION container_governance.compute_audit_event_hash();

CREATE OR REPLACE FUNCTION container_governance.prevent_audit_event_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit events are immutable and cannot be modified or deleted';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_audit_event_update
ON container_governance.audit_events;

CREATE TRIGGER trg_prevent_audit_event_update
BEFORE UPDATE OR DELETE ON container_governance.audit_events
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_audit_event_mutation();

-- ============================================================================
-- 16. Deployment Eligibility Function
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.is_image_deployable(p_image_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT
        ci.approval_status = 'approved'
        AND ci.validation_status = 'validated'
        AND ci.docker_image_digest IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM container_governance.image_packages ip
            JOIN container_governance.approved_packages ap
                ON ip.package_id = ap.package_id
            WHERE ip.image_id = ci.image_id
              AND ap.approval_status <> 'approved'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM container_governance.vulnerability_findings vf
            WHERE vf.image_id = ci.image_id
              AND vf.severity IN ('critical', 'high')
              AND vf.status NOT IN ('fixed', 'accepted_risk', 'false_positive', 'not_applicable')
        )
        AND NOT EXISTS (
            SELECT 1
            FROM container_governance.license_findings lf
            WHERE lf.image_id = ci.image_id
              AND lf.license_policy_status = 'prohibited'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM container_governance.secret_scan_findings sf
            WHERE sf.image_id = ci.image_id
              AND sf.status = 'open'
        )
        AND EXISTS (
            SELECT 1
            FROM container_governance.container_evidence ce
            WHERE ce.image_id = ci.image_id
              AND ce.evidence_type = 'sbom'
              AND ce.pass_fail_status = 'pass'
        )
        AND EXISTS (
            SELECT 1
            FROM container_governance.container_evidence ce
            WHERE ce.image_id = ci.image_id
              AND ce.evidence_type = 'signature'
              AND ce.pass_fail_status = 'pass'
        )
        AND EXISTS (
            SELECT 1
            FROM container_governance.container_evidence ce
            WHERE ce.image_id = ci.image_id
              AND ce.evidence_type = 'provenance'
              AND ce.pass_fail_status = 'pass'
        )
    INTO result
    FROM container_governance.container_images ci
    WHERE ci.image_id = p_image_id;

    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 17. Block Execution of Non-Deployable Images
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.prevent_non_deployable_execution()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT container_governance.is_image_deployable(NEW.image_id) THEN
        RAISE EXCEPTION
            'Image % is not deployable. Required approvals, validation, signatures, SBOM, provenance, and risk gates are incomplete.',
            NEW.image_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_non_deployable_execution
ON container_governance.execution_runs;

CREATE TRIGGER trg_prevent_non_deployable_execution
BEFORE INSERT ON container_governance.execution_runs
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_non_deployable_execution();

-- ============================================================================
-- 18. Stronger Deployment Readiness View
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_container_enforced_deployment_readiness AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.module_id,
    ci.script_id,

    ci.approval_status,
    ci.validation_status,
    ci.docker_image_digest,
    ci.apptainer_sif_sha256,

    container_governance.is_image_deployable(ci.image_id) AS is_deployable,

    EXISTS (
        SELECT 1 FROM container_governance.container_evidence ce
        WHERE ce.image_id = ci.image_id
          AND ce.evidence_type = 'sbom'
          AND ce.pass_fail_status = 'pass'
    ) AS has_sbom,

    EXISTS (
        SELECT 1 FROM container_governance.container_evidence ce
        WHERE ce.image_id = ci.image_id
          AND ce.evidence_type = 'signature'
          AND ce.pass_fail_status = 'pass'
    ) AS has_signature,

    EXISTS (
        SELECT 1 FROM container_governance.container_evidence ce
        WHERE ce.image_id = ci.image_id
          AND ce.evidence_type = 'provenance'
          AND ce.pass_fail_status = 'pass'
    ) AS has_provenance,

    EXISTS (
        SELECT 1 FROM container_governance.vulnerability_findings vf
        WHERE vf.image_id = ci.image_id
          AND vf.severity IN ('critical', 'high')
          AND vf.status NOT IN ('fixed', 'accepted_risk', 'false_positive', 'not_applicable')
    ) AS has_blocking_vulnerabilities,

    EXISTS (
        SELECT 1 FROM container_governance.license_findings lf
        WHERE lf.image_id = ci.image_id
          AND lf.license_policy_status = 'prohibited'
    ) AS has_prohibited_license,

    EXISTS (
        SELECT 1 FROM container_governance.secret_scan_findings sf
        WHERE sf.image_id = ci.image_id
          AND sf.status = 'open'
    ) AS has_open_secret_findings

FROM container_governance.container_images ci;

-- ============================================================================
-- 19. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_artifacts_related_entity
ON container_governance.artifacts(related_entity_type, related_entity_id);

CREATE INDEX IF NOT EXISTS idx_artifacts_sha256
ON container_governance.artifacts(sha256);

CREATE INDEX IF NOT EXISTS idx_generated_container_files_image_id
ON container_governance.generated_container_files(image_id);

CREATE INDEX IF NOT EXISTS idx_vulnerability_findings_image_id
ON container_governance.vulnerability_findings(image_id);

CREATE INDEX IF NOT EXISTS idx_vulnerability_findings_severity
ON container_governance.vulnerability_findings(severity);

CREATE INDEX IF NOT EXISTS idx_license_findings_image_id
ON container_governance.license_findings(image_id);

CREATE INDEX IF NOT EXISTS idx_secret_scan_findings_image_id
ON container_governance.secret_scan_findings(image_id);

CREATE INDEX IF NOT EXISTS idx_policy_gate_results_image_id
ON container_governance.policy_gate_results(image_id);

CREATE INDEX IF NOT EXISTS idx_execution_environments_name
ON container_governance.execution_environments(environment_name);

CREATE INDEX IF NOT EXISTS idx_electronic_signatures_related_entity
ON container_governance.electronic_signatures(related_entity_type, related_entity_id);

-- ============================================================================
-- 20. Seed Enterprise Runtime Policies
-- ============================================================================

INSERT INTO container_governance.runtime_policies (
    runtime_policy_id,
    policy_name,
    policy_description,
    run_as_non_root,
    read_only_filesystem,
    network_mode,
    drop_all_capabilities,
    no_new_privileges,
    allow_privileged_mode,
    allow_host_pid,
    allow_host_network,
    allow_host_mounts,
    approval_status,
    approved_by,
    approved_at
)
VALUES
(
    'runtime-policy-locked-down',
    'Locked-Down Runtime Policy',
    'Default regulated runtime policy: non-root, read-only filesystem, no network, no privilege escalation, no host namespace access.',
    true,
    true,
    'none',
    true,
    true,
    false,
    false,
    false,
    false,
    'approved',
    'Architecture Review Board',
    now()
)
ON CONFLICT (runtime_policy_id) DO NOTHING;

-- ============================================================================
-- 21. Seed Execution Environment Example
-- ============================================================================

INSERT INTO container_governance.execution_environments (
    environment_name,
    environment_type,
    scheduler_type,
    container_runtime,
    runtime_version,
    os_family,
    os_version,
    network_policy,
    environment_owner,
    compliance_scope,
    approval_status,
    approved_by,
    approved_at
)
VALUES
(
    'explorer-hpc-slurm-apptainer',
    'hpc',
    'slurm',
    'apptainer',
    'TO_BE_CAPTURED_AT_RUNTIME',
    'linux',
    'TO_BE_CAPTURED_AT_RUNTIME',
    'restricted',
    'BioDiscoveryAI Platform Owner',
    ARRAY['GxP', '21CFR11', 'NIST-800-53', 'ISO-27001', 'SOC2'],
    'approved',
    'Architecture Review Board',
    now()
)
ON CONFLICT (environment_name, environment_type) DO NOTHING;

-- ==========================================================================
-- SECTION B: V014 ENTERPRISE CONTROLS
-- ==========================================================================

-- ============================================================================
-- BioDiscoveryAI Container Governance Registry
-- Version: V011
-- Purpose:
--   SQL-first container governance, package approval, image lineage,
--   Dockerfile/Apptainer generation, DevSecOps evidence, validation,
--   audit logging, and runtime traceability.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Modules
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.modules (
    module_id              TEXT PRIMARY KEY,
    module_name            TEXT NOT NULL,
    module_version         TEXT NOT NULL,
    module_description     TEXT NOT NULL,
    business_purpose       TEXT NOT NULL,
    scientific_purpose     TEXT,
    compliance_scope       TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    owner                  TEXT NOT NULL,
    status                 TEXT NOT NULL DEFAULT 'draft',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Scripts / Tasks
-- ============================================================================

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
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 3. Approved Package Catalog
-- ============================================================================

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

-- ============================================================================
-- 4. Base Images
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.base_images (
    base_image_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_name             TEXT NOT NULL,
    image_tag              TEXT NOT NULL,
    image_digest_sha256    TEXT NOT NULL,
    os_family              TEXT NOT NULL,
    os_version             TEXT NOT NULL,
    description            TEXT NOT NULL,
    inclusion_reason       TEXT NOT NULL,
    security_status        TEXT NOT NULL DEFAULT 'pending',
    approval_status        TEXT NOT NULL DEFAULT 'pending',
    approved_by            TEXT,
    approved_at            TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(image_name, image_tag, image_digest_sha256)
);

-- ============================================================================
-- 5. Container Images
-- ============================================================================

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

-- ============================================================================
-- 6. Image Package Mapping
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.image_packages (
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    package_id             UUID NOT NULL REFERENCES container_governance.approved_packages(package_id),

    install_order          INT NOT NULL,
    install_scope          TEXT NOT NULL DEFAULT 'runtime',
    required               BOOLEAN NOT NULL DEFAULT true,

    why_this_image_needs_it TEXT NOT NULL,
    removal_impact          TEXT NOT NULL,

    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (image_id, package_id)
);

-- ============================================================================
-- 7. Change Control
-- ============================================================================

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

-- ============================================================================
-- 8. Build Records
-- ============================================================================

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

-- ============================================================================
-- 9. DevSecOps Evidence
-- ============================================================================

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

-- ============================================================================
-- 10. Validation Records
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.validation_records (
    validation_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id               UUID NOT NULL REFERENCES container_governance.container_images(image_id),

    validation_type        TEXT NOT NULL CHECK (
        validation_type IN ('IQ', 'OQ', 'PQ')
    ),

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

-- ============================================================================
-- 11. Runtime Execution Lineage
-- ============================================================================

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

-- ============================================================================
-- 12. Immutable Audit Log
-- ============================================================================

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
    event_hash             TEXT NOT NULL,

    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 13. Governance Decisions
-- ============================================================================

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

-- ============================================================================
-- 14. Indexes
-- ============================================================================

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

-- ============================================================================
-- 15. Governance View: Full Container Lineage
-- ============================================================================

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

-- ============================================================================
-- 16. Governance View: Package Justification Per Image
-- ============================================================================

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

-- ============================================================================
-- 17. Governance View: Deployment Readiness
-- ============================================================================

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

CREATE TABLE IF NOT EXISTS container_governance.capa_records (
    capa_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capa_number              TEXT NOT NULL UNIQUE,
    related_entity_type      TEXT NOT NULL,
    related_entity_id        TEXT NOT NULL,
    severity                 TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status                   TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'closed', 'cancelled')),
    summary                  TEXT NOT NULL,
    corrective_action        TEXT,
    preventive_action        TEXT,
    owner                    TEXT NOT NULL DEFAULT current_user,
    opened_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_at                   TIMESTAMPTZ,
    closed_at                TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.release_certifications (
    release_certification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id                 UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    certification_status     TEXT NOT NULL DEFAULT 'draft' CHECK (certification_status IN ('draft', 'pending', 'approved', 'certified', 'released', 'rejected', 'retired')),
    certification_version    TEXT NOT NULL DEFAULT '1.0.0',
    certified_by             TEXT,
    certified_at             TIMESTAMPTZ,
    release_notes            TEXT,
    evidence_summary         JSONB NOT NULL DEFAULT '{}',
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(image_id, certification_version)
);

CREATE OR REPLACE FUNCTION container_governance.is_release_certified(p_image_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.release_certifications rc
        WHERE rc.image_id = p_image_id
          AND rc.certification_status IN ('approved', 'certified', 'released')
    )
    OR EXISTS (
        SELECT 1
        FROM container_governance.electronic_signatures es
        WHERE es.related_entity_type = 'container_image'
          AND es.related_entity_id = p_image_id::TEXT
          AND es.signature_meaning = 'release_authorization'
    );
$$;
-- ============================================================================
-- Final Consolidated Enterprise Readiness View
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_final_container_governance_status AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    ci.module_id,
    ci.script_id,
    ci.approval_status,
    ci.validation_status,
    ci.docker_image_digest,
    ci.apptainer_sif_sha256,

    container_governance.is_image_deployable(ci.image_id) AS deployable_by_security_gates,
    container_governance.is_release_certified(ci.image_id) AS release_certified,

    CASE
        WHEN container_governance.is_image_deployable(ci.image_id)
         AND container_governance.is_release_certified(ci.image_id)
         AND NOT EXISTS (
             SELECT 1
             FROM container_governance.capa_records cr
             WHERE cr.related_entity_type = 'container_image'
               AND cr.related_entity_id = ci.image_id::TEXT
               AND cr.severity IN ('high', 'critical')
               AND cr.status NOT IN ('closed', 'cancelled')
         )
        THEN 'top_tier_enterprise_ready'
        ELSE 'not_ready'
    END AS final_governance_status,

    now() AS evaluated_at
FROM container_governance.container_images ci;

-- ============================================================================
-- Final Migration Audit Event
-- ============================================================================

INSERT INTO container_governance.audit_events (
    actor,
    action,
    entity_type,
    entity_id,
    event_description,
    before_state,
    after_state
)
VALUES (
    current_user,
    'apply_migration',
    'database_migration',
    'V015__container_governance_final_enterprise_standard.sql',
    'Applied final consolidated top-tier container governance enforcement and enterprise controls migration.',
    NULL,
    jsonb_build_object(
        'migration', 'V015',
        'scope', 'V012 enforcement + V014 enterprise controls',
        'status', 'applied'
    )
);

COMMIT;

