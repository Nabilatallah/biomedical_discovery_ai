-- ============================================================================
-- BioDiscoveryAI Scientific Governance
-- Migration: V035__scientific_governance.sql
-- Purpose:
--   Govern studies, protocols, hypotheses, experiments, datasets, analyses,
--   scientific claims, evidence, publications, submissions, and full lineage
--   from container/workflow execution to scientific output.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.scientific_studies (
    study_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_code TEXT NOT NULL UNIQUE,
    study_title TEXT NOT NULL,
    study_description TEXT NOT NULL,
    therapeutic_area TEXT,
    disease_context TEXT,
    study_owner TEXT NOT NULL,
    study_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (study_status IN ('draft','active','analysis','completed','archived','cancelled')),
    compliance_scope TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.study_protocols (
    protocol_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_id UUID NOT NULL REFERENCES container_governance.scientific_studies(study_id),
    protocol_version TEXT NOT NULL,
    protocol_summary TEXT NOT NULL,
    objectives JSONB NOT NULL DEFAULT '[]',
    inclusion_criteria JSONB NOT NULL DEFAULT '[]',
    exclusion_criteria JSONB NOT NULL DEFAULT '[]',
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','under_review','approved','rejected','superseded')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    artifact_uri TEXT,
    artifact_sha256 TEXT,
    UNIQUE(study_id, protocol_version)
);

CREATE TABLE IF NOT EXISTS container_governance.scientific_hypotheses (
    hypothesis_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_id UUID REFERENCES container_governance.scientific_studies(study_id),
    hypothesis_text TEXT NOT NULL,
    rationale TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'proposed'
        CHECK (status IN ('proposed','accepted_for_testing','supported','not_supported','inconclusive','retired')),
    proposed_by TEXT NOT NULL,
    proposed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.scientific_datasets (
    scientific_dataset_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_id UUID REFERENCES container_governance.scientific_studies(study_id),
    dataset_name TEXT NOT NULL,
    dataset_version TEXT NOT NULL,
    dataset_type TEXT NOT NULL,
    data_classification TEXT NOT NULL CHECK (
        data_classification IN ('public','internal','confidential','regulated','phi','pii')
    ),
    source_description TEXT NOT NULL,
    owner TEXT NOT NULL,
    uri TEXT NOT NULL,
    sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(dataset_name, dataset_version)
);

CREATE TABLE IF NOT EXISTS container_governance.scientific_analyses (
    scientific_analysis_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_id UUID REFERENCES container_governance.scientific_studies(study_id),
    hypothesis_id UUID REFERENCES container_governance.scientific_hypotheses(hypothesis_id),
    analysis_name TEXT NOT NULL,
    analysis_description TEXT NOT NULL,
    execution_run_id UUID REFERENCES container_governance.execution_runs(execution_run_id),
    primary_dataset_id UUID REFERENCES container_governance.scientific_datasets(scientific_dataset_id),
    analysis_status TEXT NOT NULL DEFAULT 'planned'
        CHECK (analysis_status IN ('planned','running','completed','failed','reviewed','rejected')),
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.scientific_claims (
    scientific_claim_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_id UUID REFERENCES container_governance.scientific_studies(study_id),
    scientific_analysis_id UUID REFERENCES container_governance.scientific_analyses(scientific_analysis_id),
    claim_text TEXT NOT NULL,
    confidence_level TEXT NOT NULL CHECK (confidence_level IN ('low','medium','high','validated')),
    evidence_summary TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','under_review','accepted','rejected','superseded')),
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.scientific_reviews (
    scientific_review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type TEXT NOT NULL,
    related_entity_id TEXT NOT NULL,
    reviewer_identity TEXT NOT NULL,
    reviewer_role TEXT NOT NULL,
    review_decision TEXT NOT NULL CHECK (review_decision IN ('approved','rejected','needs_revision')),
    review_comments TEXT NOT NULL,
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.publication_records (
    publication_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    study_id UUID REFERENCES container_governance.scientific_studies(study_id),
    title TEXT NOT NULL,
    publication_type TEXT NOT NULL CHECK (publication_type IN ('abstract','poster','manuscript','preprint','regulatory_submission','internal_report')),
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','under_review','submitted','accepted','published','rejected','withdrawn')),
    artifact_uri TEXT,
    artifact_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW container_governance.v_scientific_lineage AS
SELECT
    ss.study_code,
    ss.study_title,
    sh.hypothesis_text,
    sa.analysis_name,
    sa.execution_run_id,
    er.image_id,
    ci.image_name,
    ci.image_version,
    sc.claim_text,
    sc.confidence_level,
    sc.status AS claim_status
FROM container_governance.scientific_studies ss
LEFT JOIN container_governance.scientific_hypotheses sh ON sh.study_id = ss.study_id
LEFT JOIN container_governance.scientific_analyses sa ON sa.hypothesis_id = sh.hypothesis_id
LEFT JOIN container_governance.execution_runs er ON er.execution_run_id = sa.execution_run_id
LEFT JOIN container_governance.container_images ci ON ci.image_id = er.image_id
LEFT JOIN container_governance.scientific_claims sc ON sc.scientific_analysis_id = sa.scientific_analysis_id;

CREATE INDEX IF NOT EXISTS idx_scientific_studies_code ON container_governance.scientific_studies(study_code);
CREATE INDEX IF NOT EXISTS idx_scientific_analyses_run ON container_governance.scientific_analyses(execution_run_id);
CREATE INDEX IF NOT EXISTS idx_scientific_claims_status ON container_governance.scientific_claims(status);

COMMIT;
