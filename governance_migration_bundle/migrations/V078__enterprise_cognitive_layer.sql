-- ============================================================================
-- BioDiscoveryAI Enterprise Cognitive Layer
-- Migration: V084__enterprise_cognitive_layer.sql
-- Purpose:
--   Register enterprise knowledge synthesis jobs, cognitive summaries,
--   executive recommendations, cross-domain reasoning outputs, narrative
--   generation, and decision-support evidence across the governance platform.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS cognitive_governance;

CREATE TABLE IF NOT EXISTS cognitive_governance.cognitive_capabilities (
    cognitive_capability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capability_code TEXT NOT NULL UNIQUE,
    capability_name TEXT NOT NULL,
    capability_description TEXT NOT NULL,
    capability_type TEXT NOT NULL CHECK (
        capability_type IN ('summarization','reasoning','recommendation','risk_synthesis','executive_briefing','question_answering','other')
    ),
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high','critical')),
    human_review_required BOOLEAN NOT NULL DEFAULT true,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cognitive_governance.cognitive_jobs (
    cognitive_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognitive_capability_id UUID NOT NULL REFERENCES cognitive_governance.cognitive_capabilities(cognitive_capability_id),
    job_name TEXT NOT NULL,
    job_description TEXT NOT NULL,
    input_scope JSONB NOT NULL DEFAULT '{}',
    requested_by TEXT NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    job_status TEXT NOT NULL DEFAULT 'requested'
        CHECK (job_status IN ('requested','running','completed','failed','cancelled','blocked')),
    output_uri TEXT,
    output_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS cognitive_governance.cognitive_outputs (
    cognitive_output_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognitive_job_id UUID NOT NULL REFERENCES cognitive_governance.cognitive_jobs(cognitive_job_id),
    output_type TEXT NOT NULL CHECK (
        output_type IN ('summary','recommendation','risk_brief','executive_brief','decision_support','answer','narrative','other')
    ),
    output_title TEXT NOT NULL,
    output_summary TEXT NOT NULL,
    output_payload JSONB NOT NULL DEFAULT '{}',
    confidence_level TEXT NOT NULL CHECK (confidence_level IN ('low','medium','high')),
    human_review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (human_review_status IN ('pending','approved','rejected','not_required')),
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cognitive_governance.cognitive_evidence_links (
    cognitive_evidence_link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognitive_output_id UUID NOT NULL REFERENCES cognitive_governance.cognitive_outputs(cognitive_output_id),
    evidence_entity_type TEXT NOT NULL,
    evidence_entity_id TEXT NOT NULL,
    evidence_summary TEXT NOT NULL,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cognitive_governance.executive_recommendations (
    executive_recommendation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognitive_output_id UUID REFERENCES cognitive_governance.cognitive_outputs(cognitive_output_id),
    recommendation_title TEXT NOT NULL,
    recommendation_summary TEXT NOT NULL,
    recommended_action TEXT NOT NULL,
    priority TEXT NOT NULL CHECK (priority IN ('low','medium','high','critical')),
    decision_required_by DATE,
    owner TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'proposed'
        CHECK (status IN ('proposed','accepted','rejected','implemented','deferred','retired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW cognitive_governance.v_cognitive_output_review AS
SELECT
    cc.capability_code,
    cc.capability_name,
    cj.job_name,
    co.output_type,
    co.output_title,
    co.confidence_level,
    co.human_review_status,
    COUNT(cel.cognitive_evidence_link_id) AS evidence_links
FROM cognitive_governance.cognitive_outputs co
JOIN cognitive_governance.cognitive_jobs cj ON cj.cognitive_job_id = co.cognitive_job_id
JOIN cognitive_governance.cognitive_capabilities cc ON cc.cognitive_capability_id = cj.cognitive_capability_id
LEFT JOIN cognitive_governance.cognitive_evidence_links cel ON cel.cognitive_output_id = co.cognitive_output_id
GROUP BY cc.capability_code, cc.capability_name, cj.job_name, co.output_type, co.output_title, co.confidence_level, co.human_review_status;

INSERT INTO cognitive_governance.cognitive_capabilities (
    capability_code, capability_name, capability_description, capability_type, risk_level, human_review_required, owner, approval_status, approved_by, approved_at
)
VALUES
('EXEC_GOV_BRIEF','Executive Governance Briefing','Generate human-reviewed executive summaries across risk, compliance, AI, vendors, studies, submissions, and operations.','executive_briefing','high',true,'Executive Governance','approved','Architecture Review Board',now()),
('CROSS_DOMAIN_RISK_SYNTHESIS','Cross-Domain Risk Synthesis','Synthesize risk implications across vendors, models, data, containers, studies, and submissions.','risk_synthesis','high',true,'Enterprise Risk','approved','Architecture Review Board',now())
ON CONFLICT (capability_code) DO NOTHING;

COMMIT;
