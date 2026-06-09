-- ============================================================================
-- BioDiscoveryAI Container Governance Automation
-- Migration: V016__container_governance_automation.sql
-- Purpose:
--   SQL-first automation control plane for Dockerfile/Apptainer generation,
--   package resolution, build orchestration, scan orchestration, signing,
--   provenance, deployment gates, event-driven automation, retries, and
--   runbook/task traceability.
--
-- Dependencies:
--   V011__container_governance_registry.sql
--   V015__container_governance_final_enterprise_standard.sql
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Automation Service Accounts
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.automation_service_accounts (
    service_account_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_account_name      TEXT NOT NULL UNIQUE,
    service_account_type      TEXT NOT NULL CHECK (
        service_account_type IN ('generator', 'builder', 'scanner', 'signer', 'publisher', 'scheduler', 'auditor', 'system')
    ),
    description               TEXT NOT NULL,
    owner                     TEXT NOT NULL,
    allowed_actions           TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    least_privilege_scope     JSONB NOT NULL DEFAULT '{}',
    credential_reference      TEXT,
    credential_storage        TEXT NOT NULL DEFAULT 'external_secret_manager',
    rotation_interval_days    INT NOT NULL DEFAULT 90 CHECK (rotation_interval_days > 0),
    last_rotated_at           TIMESTAMPTZ,
    active                    BOOLEAN NOT NULL DEFAULT true,
    approval_status           TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by               TEXT,
    approved_at               TIMESTAMPTZ,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Automation Pipelines
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.automation_pipelines (
    automation_pipeline_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_name             TEXT NOT NULL UNIQUE,
    pipeline_description      TEXT NOT NULL,
    pipeline_type             TEXT NOT NULL CHECK (
        pipeline_type IN ('dockerfile_generation', 'apptainer_generation', 'image_build', 'scan', 'sign', 'publish', 'release', 'full_container_lifecycle')
    ),
    orchestrator              TEXT NOT NULL CHECK (orchestrator IN ('nextflow', 'github_actions', 'jenkins', 'gitlab_ci', 'argo', 'manual_sql', 'other')),
    source_repository         TEXT NOT NULL,
    pipeline_definition_uri   TEXT NOT NULL,
    pipeline_definition_sha256 TEXT NOT NULL,
    default_runtime_policy_id TEXT REFERENCES container_governance.runtime_policies(runtime_policy_id),
    approval_required         BOOLEAN NOT NULL DEFAULT true,
    active                    BOOLEAN NOT NULL DEFAULT true,
    created_by                TEXT NOT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.automation_pipeline_steps (
    automation_step_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_pipeline_id    UUID NOT NULL REFERENCES container_governance.automation_pipelines(automation_pipeline_id),
    step_order                INT NOT NULL CHECK (step_order > 0),
    step_name                 TEXT NOT NULL,
    step_description          TEXT NOT NULL,
    step_type                 TEXT NOT NULL CHECK (
        step_type IN ('validate_contract', 'resolve_packages', 'generate_dockerfile', 'generate_apptainer_def', 'build_docker_image', 'build_apptainer_sif', 'generate_sbom', 'scan_vulnerabilities', 'scan_licenses', 'scan_secrets', 'sign_artifact', 'generate_provenance', 'publish_registry', 'certify_release', 'notify', 'archive_evidence')
    ),
    required                  BOOLEAN NOT NULL DEFAULT true,
    blocking                  BOOLEAN NOT NULL DEFAULT true,
    max_retries               INT NOT NULL DEFAULT 0 CHECK (max_retries >= 0),
    timeout_minutes           INT NOT NULL DEFAULT 60 CHECK (timeout_minutes > 0),
    expected_evidence_type    TEXT,
    policy_gate_name          TEXT,
    UNIQUE(automation_pipeline_id, step_order)
);

-- ============================================================================
-- 3. Automation Requests and Runs
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.automation_requests (
    automation_request_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_pipeline_id    UUID NOT NULL REFERENCES container_governance.automation_pipelines(automation_pipeline_id),
    image_id                  UUID REFERENCES container_governance.container_images(image_id),
    module_id                 TEXT REFERENCES container_governance.modules(module_id),
    script_id                 TEXT REFERENCES container_governance.scripts(script_id),
    requested_action          TEXT NOT NULL,
    request_reason            TEXT NOT NULL,
    requested_by              TEXT NOT NULL,
    requested_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    priority                  TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    request_parameters        JSONB NOT NULL DEFAULT '{}',
    status                    TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'approved', 'rejected', 'queued', 'running', 'completed', 'failed', 'cancelled')),
    approved_by               TEXT,
    approved_at               TIMESTAMPTZ,
    rejection_reason          TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.automation_runs (
    automation_run_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_request_id     UUID NOT NULL REFERENCES container_governance.automation_requests(automation_request_id),
    automation_pipeline_id    UUID NOT NULL REFERENCES container_governance.automation_pipelines(automation_pipeline_id),
    image_id                  UUID REFERENCES container_governance.container_images(image_id),
    build_id                  UUID REFERENCES container_governance.image_builds(build_id),
    execution_environment_id  UUID REFERENCES container_governance.execution_environments(environment_id),
    service_account_id        UUID REFERENCES container_governance.automation_service_accounts(service_account_id),
    run_status                TEXT NOT NULL DEFAULT 'started' CHECK (run_status IN ('started', 'running', 'passed', 'failed', 'cancelled', 'blocked')),
    started_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at               TIMESTAMPTZ,
    trigger_source            TEXT NOT NULL CHECK (trigger_source IN ('manual', 'git_commit', 'schedule', 'cve_event', 'policy_change', 'validation_expiry', 'api', 'system')),
    trigger_reference         TEXT,
    run_parameters            JSONB NOT NULL DEFAULT '{}',
    run_log_uri               TEXT,
    run_log_sha256            TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.automation_step_runs (
    automation_step_run_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_run_id         UUID NOT NULL REFERENCES container_governance.automation_runs(automation_run_id),
    automation_step_id        UUID NOT NULL REFERENCES container_governance.automation_pipeline_steps(automation_step_id),
    step_status               TEXT NOT NULL DEFAULT 'started' CHECK (step_status IN ('started', 'running', 'passed', 'failed', 'warning', 'skipped', 'cancelled', 'blocked')),
    started_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at               TIMESTAMPTZ,
    attempt_number            INT NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
    exit_code                 INT,
    output_summary            JSONB NOT NULL DEFAULT '{}',
    evidence_id               UUID REFERENCES container_governance.container_evidence(evidence_id),
    artifact_id               UUID REFERENCES container_governance.artifacts(artifact_id),
    failure_reason            TEXT,
    UNIQUE(automation_run_id, automation_step_id, attempt_number)
);

-- ============================================================================
-- 4. Generator Templates and Rendered Outputs
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.container_file_templates (
    template_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name             TEXT NOT NULL UNIQUE,
    template_type             TEXT NOT NULL CHECK (template_type IN ('dockerfile', 'apptainer_definition', 'nextflow_process', 'slurm_wrapper', 'build_script')),
    template_version          TEXT NOT NULL,
    template_uri              TEXT NOT NULL,
    template_sha256           TEXT NOT NULL,
    template_engine           TEXT NOT NULL DEFAULT 'jinja2',
    description               TEXT NOT NULL,
    approval_status           TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by               TEXT,
    approved_at               TIMESTAMPTZ,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(template_name, template_version)
);

CREATE TABLE IF NOT EXISTS container_governance.container_file_render_events (
    render_event_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id               UUID NOT NULL REFERENCES container_governance.container_file_templates(template_id),
    image_id                  UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    automation_run_id         UUID REFERENCES container_governance.automation_runs(automation_run_id),
    rendered_file_type        TEXT NOT NULL CHECK (rendered_file_type IN ('dockerfile', 'apptainer_definition', 'nextflow_process', 'slurm_wrapper', 'build_script')),
    rendered_file_uri         TEXT NOT NULL,
    rendered_file_sha256      TEXT NOT NULL,
    render_parameters         JSONB NOT NULL DEFAULT '{}',
    rendered_by               TEXT NOT NULL,
    rendered_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(image_id, rendered_file_type, rendered_file_sha256)
);

-- ============================================================================
-- 5. Event Queue for SQL-Driven Automation
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.automation_event_queue (
    automation_event_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type                TEXT NOT NULL CHECK (
        event_type IN ('image_created', 'package_approved', 'base_image_updated', 'dockerfile_generated', 'build_completed', 'scan_completed', 'signature_completed', 'release_certified', 'cve_detected', 'validation_expiring', 'waiver_expiring', 'backup_validation_due')
    ),
    related_entity_type       TEXT NOT NULL,
    related_entity_id         TEXT NOT NULL,
    event_payload             JSONB NOT NULL DEFAULT '{}',
    event_status              TEXT NOT NULL DEFAULT 'pending' CHECK (event_status IN ('pending', 'claimed', 'processed', 'failed', 'cancelled')),
    available_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_by                TEXT,
    claimed_at                TIMESTAMPTZ,
    processed_at              TIMESTAMPTZ,
    failure_reason            TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 6. Automation Gate Matrix
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.automation_gate_requirements (
    gate_requirement_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lifecycle_phase           TEXT NOT NULL CHECK (lifecycle_phase IN ('pre_generation', 'pre_build', 'post_build', 'pre_publish', 'pre_release', 'pre_execution')),
    gate_name                 TEXT NOT NULL,
    gate_description          TEXT NOT NULL,
    required_evidence_type    TEXT,
    blocking                  BOOLEAN NOT NULL DEFAULT true,
    minimum_status            TEXT NOT NULL DEFAULT 'pass',
    applies_to_image_type     TEXT NOT NULL DEFAULT 'all' CHECK (applies_to_image_type IN ('all', 'docker', 'apptainer')),
    active                    BOOLEAN NOT NULL DEFAULT true,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(lifecycle_phase, gate_name)
);

INSERT INTO container_governance.automation_gate_requirements (
    lifecycle_phase, gate_name, gate_description, required_evidence_type, blocking, minimum_status
)
VALUES
('pre_generation', 'approved_base_image', 'Base image must be approved and digest-pinned before file generation.', NULL, true, 'pass'),
('pre_generation', 'approved_package_catalog', 'All packages must exist in the approved package catalog.', NULL, true, 'pass'),
('pre_build', 'generated_file_hash_recorded', 'Generated Dockerfile/Apptainer file hash must be recorded.', NULL, true, 'pass'),
('post_build', 'sbom_required', 'SBOM must be generated after build.', 'sbom', true, 'pass'),
('post_build', 'vulnerability_scan_required', 'Vulnerability scan must complete after build.', 'vulnerability_scan', true, 'pass'),
('post_build', 'license_scan_required', 'License scan must complete after build.', 'license_scan', true, 'pass'),
('post_build', 'secret_scan_required', 'Secret scan must complete after build.', 'secret_scan', true, 'pass'),
('pre_publish', 'signature_required', 'Image/artifact must be signed before registry publication.', 'signature', true, 'pass'),
('pre_publish', 'provenance_required', 'SLSA/in-toto provenance must be available before publication.', 'provenance', true, 'pass'),
('pre_release', 'release_certification_required', 'Release certification must be complete before regulated execution.', 'approval_record', true, 'pass')
ON CONFLICT (lifecycle_phase, gate_name) DO NOTHING;

-- ============================================================================
-- 7. Helper Views
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_automation_run_status AS
SELECT
    ar.automation_run_id,
    ar.run_status,
    ar.trigger_source,
    ar.started_at,
    ar.finished_at,
    ap.pipeline_name,
    ap.pipeline_type,
    ci.image_name,
    ci.image_version,
    COUNT(asr.automation_step_run_id) AS step_count,
    COUNT(asr.automation_step_run_id) FILTER (WHERE asr.step_status = 'passed') AS passed_steps,
    COUNT(asr.automation_step_run_id) FILTER (WHERE asr.step_status = 'failed') AS failed_steps,
    COUNT(asr.automation_step_run_id) FILTER (WHERE asr.step_status = 'blocked') AS blocked_steps
FROM container_governance.automation_runs ar
JOIN container_governance.automation_pipelines ap ON ar.automation_pipeline_id = ap.automation_pipeline_id
LEFT JOIN container_governance.container_images ci ON ar.image_id = ci.image_id
LEFT JOIN container_governance.automation_step_runs asr ON ar.automation_run_id = asr.automation_run_id
GROUP BY ar.automation_run_id, ar.run_status, ar.trigger_source, ar.started_at, ar.finished_at, ap.pipeline_name, ap.pipeline_type, ci.image_name, ci.image_version;

CREATE OR REPLACE VIEW container_governance.v_pending_automation_events AS
SELECT *
FROM container_governance.automation_event_queue
WHERE event_status = 'pending'
  AND available_at <= now()
ORDER BY available_at ASC, created_at ASC;

-- ============================================================================
-- 8. Triggers: Queue Events
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.queue_image_created_event()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO container_governance.automation_event_queue (
        event_type, related_entity_type, related_entity_id, event_payload
    ) VALUES (
        'image_created', 'container_image', NEW.image_id::TEXT,
        jsonb_build_object('image_name', NEW.image_name, 'image_version', NEW.image_version, 'module_id', NEW.module_id, 'script_id', NEW.script_id)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_queue_image_created_event ON container_governance.container_images;
CREATE TRIGGER trg_queue_image_created_event
AFTER INSERT ON container_governance.container_images
FOR EACH ROW
EXECUTE FUNCTION container_governance.queue_image_created_event();

CREATE OR REPLACE FUNCTION container_governance.queue_build_completed_event()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.build_status IN ('passed', 'failed') AND (OLD.build_status IS DISTINCT FROM NEW.build_status) THEN
        INSERT INTO container_governance.automation_event_queue (
            event_type, related_entity_type, related_entity_id, event_payload
        ) VALUES (
            'build_completed', 'image_build', NEW.build_id::TEXT,
            jsonb_build_object('image_id', NEW.image_id, 'build_status', NEW.build_status, 'docker_image_digest', NEW.docker_image_digest)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_queue_build_completed_event ON container_governance.image_builds;
CREATE TRIGGER trg_queue_build_completed_event
AFTER UPDATE ON container_governance.image_builds
FOR EACH ROW
EXECUTE FUNCTION container_governance.queue_build_completed_event();

-- ============================================================================
-- 9. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_automation_requests_status ON container_governance.automation_requests(status, requested_at);
CREATE INDEX IF NOT EXISTS idx_automation_runs_image ON container_governance.automation_runs(image_id);
CREATE INDEX IF NOT EXISTS idx_automation_runs_status ON container_governance.automation_runs(run_status, started_at);
CREATE INDEX IF NOT EXISTS idx_automation_step_runs_run ON container_governance.automation_step_runs(automation_run_id);
CREATE INDEX IF NOT EXISTS idx_automation_event_queue_status ON container_governance.automation_event_queue(event_status, available_at);
CREATE INDEX IF NOT EXISTS idx_container_file_render_events_image ON container_governance.container_file_render_events(image_id);

COMMIT;
