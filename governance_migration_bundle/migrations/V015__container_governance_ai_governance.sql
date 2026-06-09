-- ============================================================================
-- BioDiscoveryAI Container Governance AI Governance
-- Migration: V017__container_governance_ai_governance.sql
-- Purpose:
--   Govern AI-assisted container and code generation: AI agent identity,
--   prompts, model/provider lineage, tool permissions, human review,
--   generated code risk classification, AI red-team records, model risk controls,
--   NIST AI RMF/EU AI Act/SR 11-7 style traceability, and audit evidence.
--
-- Dependencies:
--   V011, V015, V016
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. AI Providers, Models, and Agents
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.ai_providers (
    ai_provider_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_name            TEXT NOT NULL UNIQUE,
    provider_type            TEXT NOT NULL CHECK (provider_type IN ('openai', 'azure_openai', 'anthropic', 'google', 'local', 'other')),
    provider_endpoint_class   TEXT NOT NULL DEFAULT 'external_api' CHECK (provider_endpoint_class IN ('external_api', 'private_endpoint', 'local_runtime')),
    data_retention_summary    TEXT NOT NULL,
    privacy_assessment_status TEXT NOT NULL DEFAULT 'pending' CHECK (privacy_assessment_status IN ('pending', 'approved', 'rejected', 'expired')),
    vendor_risk_status        TEXT NOT NULL DEFAULT 'pending' CHECK (vendor_risk_status IN ('pending', 'approved', 'rejected', 'expired')),
    approved_by               TEXT,
    approved_at               TIMESTAMPTZ,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.ai_models (
    ai_model_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_provider_id           UUID NOT NULL REFERENCES container_governance.ai_providers(ai_provider_id),
    model_name               TEXT NOT NULL,
    model_version            TEXT NOT NULL,
    model_family             TEXT,
    intended_use             TEXT NOT NULL,
    prohibited_use           TEXT NOT NULL,
    risk_tier                TEXT NOT NULL CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),
    validation_status        TEXT NOT NULL DEFAULT 'not_validated' CHECK (validation_status IN ('not_validated', 'validated', 'restricted', 'retired')),
    approval_status          TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(ai_provider_id, model_name, model_version)
);

CREATE TABLE IF NOT EXISTS container_governance.ai_agents (
    ai_agent_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_name               TEXT NOT NULL UNIQUE,
    agent_type               TEXT NOT NULL CHECK (agent_type IN ('codex_cli', 'code_assistant', 'review_agent', 'security_agent', 'documentation_agent', 'other')),
    ai_model_id              UUID REFERENCES container_governance.ai_models(ai_model_id),
    agent_purpose            TEXT NOT NULL,
    allowed_repositories     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    allowed_tools            TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    denied_tools             TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    max_autonomy_level       TEXT NOT NULL DEFAULT 'human_review_required' CHECK (max_autonomy_level IN ('suggest_only', 'edit_with_review', 'human_review_required', 'autonomous_low_risk_only')),
    secrets_access_allowed   BOOLEAN NOT NULL DEFAULT false,
    production_write_allowed BOOLEAN NOT NULL DEFAULT false,
    approval_status          TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. AI-Assisted Sessions and Prompt Lineage
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.ai_development_sessions (
    ai_session_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_agent_id              UUID NOT NULL REFERENCES container_governance.ai_agents(ai_agent_id),
    related_module_id        TEXT REFERENCES container_governance.modules(module_id),
    related_image_id         UUID REFERENCES container_governance.container_images(image_id),
    repository_uri           TEXT NOT NULL,
    git_branch               TEXT NOT NULL,
    starting_git_commit      TEXT NOT NULL,
    ending_git_commit        TEXT,
    session_purpose          TEXT NOT NULL,
    session_risk_level       TEXT NOT NULL CHECK (session_risk_level IN ('low', 'medium', 'high', 'critical')),
    human_operator           TEXT NOT NULL,
    started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at                 TIMESTAMPTZ,
    session_status           TEXT NOT NULL DEFAULT 'started' CHECK (session_status IN ('started', 'completed', 'failed', 'abandoned', 'rejected')),
    audit_artifact_uri       TEXT,
    audit_artifact_sha256    TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.ai_prompt_records (
    prompt_record_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_session_id            UUID NOT NULL REFERENCES container_governance.ai_development_sessions(ai_session_id),
    prompt_sequence          INT NOT NULL CHECK (prompt_sequence > 0),
    prompt_classification    TEXT NOT NULL CHECK (prompt_classification IN ('architecture', 'code_generation', 'code_review', 'security_review', 'debugging', 'documentation', 'sql_generation', 'other')),
    prompt_text_hash         TEXT NOT NULL,
    prompt_storage_uri       TEXT,
    contains_sensitive_data  BOOLEAN NOT NULL DEFAULT false,
    sensitivity_review       TEXT NOT NULL DEFAULT 'not_required' CHECK (sensitivity_review IN ('not_required', 'passed', 'failed', 'redacted')),
    created_by               TEXT NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(ai_session_id, prompt_sequence)
);

CREATE TABLE IF NOT EXISTS container_governance.ai_output_records (
    ai_output_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_record_id         UUID NOT NULL REFERENCES container_governance.ai_prompt_records(prompt_record_id),
    output_type              TEXT NOT NULL CHECK (output_type IN ('code', 'sql', 'dockerfile', 'apptainer_definition', 'documentation', 'analysis', 'test', 'other')),
    output_hash              TEXT NOT NULL,
    output_storage_uri       TEXT,
    generated_files          JSONB NOT NULL DEFAULT '[]',
    accepted_by_human        BOOLEAN NOT NULL DEFAULT false,
    accepted_by              TEXT,
    accepted_at              TIMESTAMPTZ,
    rejection_reason         TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 3. AI-Generated Change Review
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.ai_generated_change_reviews (
    ai_change_review_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_session_id            UUID NOT NULL REFERENCES container_governance.ai_development_sessions(ai_session_id),
    related_entity_type      TEXT NOT NULL,
    related_entity_id        TEXT NOT NULL,
    changed_files            JSONB NOT NULL DEFAULT '[]',
    diff_artifact_uri        TEXT NOT NULL,
    diff_artifact_sha256     TEXT NOT NULL,
    static_analysis_status   TEXT NOT NULL DEFAULT 'not_run' CHECK (static_analysis_status IN ('not_run', 'pass', 'fail', 'warning')),
    security_review_status   TEXT NOT NULL DEFAULT 'not_run' CHECK (security_review_status IN ('not_run', 'pass', 'fail', 'warning')),
    qa_review_status         TEXT NOT NULL DEFAULT 'not_run' CHECK (qa_review_status IN ('not_run', 'pass', 'fail', 'warning')),
    human_review_required    BOOLEAN NOT NULL DEFAULT true,
    human_review_status      TEXT NOT NULL DEFAULT 'pending' CHECK (human_review_status IN ('pending', 'approved', 'rejected', 'changes_requested')),
    reviewed_by              TEXT,
    reviewed_at              TIMESTAMPTZ,
    review_notes             TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 4. AI Risk Controls and Framework Mapping
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.ai_control_framework_mappings (
    ai_control_mapping_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    framework_name           TEXT NOT NULL CHECK (framework_name IN ('NIST_AI_RMF', 'EU_AI_ACT', 'SR_11_7', 'ISO_42001', 'GxP', '21CFR11', 'SOC2', 'ISO27001')),
    framework_control_id     TEXT NOT NULL,
    control_title            TEXT NOT NULL,
    control_description      TEXT NOT NULL,
    implementation_table     TEXT NOT NULL,
    implementation_notes     TEXT NOT NULL,
    evidence_query           TEXT,
    active                   BOOLEAN NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(framework_name, framework_control_id)
);

CREATE TABLE IF NOT EXISTS container_governance.ai_model_risk_assessments (
    ai_model_risk_assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_model_id              UUID NOT NULL REFERENCES container_governance.ai_models(ai_model_id),
    assessment_name          TEXT NOT NULL,
    assessment_type          TEXT NOT NULL CHECK (assessment_type IN ('initial', 'periodic', 'material_change', 'incident_driven', 'retirement')),
    risk_summary             TEXT NOT NULL,
    limitations              TEXT NOT NULL,
    failure_modes            TEXT NOT NULL,
    human_oversight_controls TEXT NOT NULL,
    validation_evidence_uri  TEXT,
    validation_evidence_sha256 TEXT,
    assessment_status        TEXT NOT NULL DEFAULT 'draft' CHECK (assessment_status IN ('draft', 'approved', 'rejected', 'expired')),
    assessed_by              TEXT NOT NULL,
    approved_by              TEXT,
    assessed_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at               TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.ai_red_team_records (
    ai_red_team_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_agent_id              UUID REFERENCES container_governance.ai_agents(ai_agent_id),
    ai_model_id              UUID REFERENCES container_governance.ai_models(ai_model_id),
    test_name                TEXT NOT NULL,
    test_category            TEXT NOT NULL CHECK (test_category IN ('prompt_injection', 'secret_exfiltration', 'unsafe_code', 'policy_bypass', 'data_leakage', 'hallucinated_dependency', 'supply_chain_risk', 'other')),
    test_description         TEXT NOT NULL,
    expected_safe_behavior   TEXT NOT NULL,
    observed_behavior        TEXT NOT NULL,
    severity                 TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status                   TEXT NOT NULL CHECK (status IN ('pass', 'fail', 'accepted_risk', 'remediated')),
    remediation_plan         TEXT,
    evidence_uri             TEXT,
    evidence_sha256          TEXT,
    tested_by                TEXT NOT NULL,
    tested_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5. AI Policy Enforcement
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.is_ai_change_review_approved(p_session_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT NOT EXISTS (
        SELECT 1
        FROM container_governance.ai_generated_change_reviews r
        WHERE r.ai_session_id = p_session_id
          AND (r.human_review_required = true AND r.human_review_status <> 'approved')
    ) INTO result;
    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION container_governance.prevent_unreviewed_ai_release_certification()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM container_governance.ai_development_sessions s
        WHERE s.related_image_id = NEW.image_id
          AND s.session_status = 'completed'
          AND NOT container_governance.is_ai_change_review_approved(s.ai_session_id)
    ) THEN
        RAISE EXCEPTION 'Image % has AI-generated changes without approved human review.', NEW.image_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_unreviewed_ai_release_certification ON container_governance.release_certifications;
CREATE TRIGGER trg_prevent_unreviewed_ai_release_certification
BEFORE INSERT OR UPDATE ON container_governance.release_certifications
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_unreviewed_ai_release_certification();

-- ============================================================================
-- 6. Views and Seeds
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_ai_governance_lineage AS
SELECT
    s.ai_session_id,
    a.agent_name,
    m.model_name,
    m.model_version,
    s.related_module_id,
    s.related_image_id,
    s.repository_uri,
    s.starting_git_commit,
    s.ending_git_commit,
    s.session_risk_level,
    s.human_operator,
    s.session_status,
    COUNT(DISTINCT p.prompt_record_id) AS prompt_count,
    COUNT(DISTINCT o.ai_output_id) AS output_count,
    COUNT(DISTINCT r.ai_change_review_id) AS review_count,
    BOOL_AND(COALESCE(r.human_review_status = 'approved', true)) AS all_reviews_approved
FROM container_governance.ai_development_sessions s
JOIN container_governance.ai_agents a ON s.ai_agent_id = a.ai_agent_id
LEFT JOIN container_governance.ai_models m ON a.ai_model_id = m.ai_model_id
LEFT JOIN container_governance.ai_prompt_records p ON s.ai_session_id = p.ai_session_id
LEFT JOIN container_governance.ai_output_records o ON p.prompt_record_id = o.prompt_record_id
LEFT JOIN container_governance.ai_generated_change_reviews r ON s.ai_session_id = r.ai_session_id
GROUP BY s.ai_session_id, a.agent_name, m.model_name, m.model_version, s.related_module_id, s.related_image_id, s.repository_uri, s.starting_git_commit, s.ending_git_commit, s.session_risk_level, s.human_operator, s.session_status;

INSERT INTO container_governance.ai_control_framework_mappings (
    framework_name, framework_control_id, control_title, control_description, implementation_table, implementation_notes
)
VALUES
('NIST_AI_RMF', 'GOVERN-1', 'AI governance policies', 'AI-assisted code generation must be governed by documented roles, approvals, and evidence.', 'ai_agents, ai_development_sessions, ai_generated_change_reviews', 'Tracks agent identity, session purpose, and human review.'),
('NIST_AI_RMF', 'MAP-1', 'AI context and risk mapping', 'AI usage context, intended use, and risk level must be documented.', 'ai_models, ai_model_risk_assessments', 'Captures model purpose, limitations, and risk tier.'),
('EU_AI_ACT', 'HUMAN_OVERSIGHT', 'Human oversight', 'Human review is required before AI-generated code can be released.', 'ai_generated_change_reviews', 'Release certification trigger blocks unreviewed AI changes.'),
('SR_11_7', 'MODEL_RISK_MANAGEMENT', 'Model risk management', 'AI model limitations, validation, and change impact must be recorded.', 'ai_model_risk_assessments', 'Supports model-risk assessment records.'),
('21CFR11', 'ELECTRONIC_RECORDS', 'Electronic records and signatures', 'AI-generated change evidence must be traceable and signed where required.', 'ai_prompt_records, ai_output_records, electronic_signatures', 'Prompt/output hashes and evidence URIs support traceability.')
ON CONFLICT (framework_name, framework_control_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_ai_sessions_image ON container_governance.ai_development_sessions(related_image_id);
CREATE INDEX IF NOT EXISTS idx_ai_prompt_records_session ON container_governance.ai_prompt_records(ai_session_id);
CREATE INDEX IF NOT EXISTS idx_ai_output_records_prompt ON container_governance.ai_output_records(prompt_record_id);
CREATE INDEX IF NOT EXISTS idx_ai_change_reviews_session ON container_governance.ai_generated_change_reviews(ai_session_id);
CREATE INDEX IF NOT EXISTS idx_ai_red_team_model ON container_governance.ai_red_team_records(ai_model_id);

COMMIT;
