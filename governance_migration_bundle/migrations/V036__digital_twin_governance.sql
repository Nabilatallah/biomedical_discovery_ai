-- ============================================================================
-- BioDiscoveryAI Digital Twin Governance
-- Migration: V038__digital_twin_governance.sql
-- Purpose:
--   Govern digital twins, twin models, twin versions, simulations, validation,
--   risk assessments, review cycles, scientific/clinical scope, and lineage
--   to data, containers, workflows, and claims.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.digital_twins (
    digital_twin_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    twin_code TEXT NOT NULL UNIQUE,
    twin_name TEXT NOT NULL,
    twin_type TEXT NOT NULL CHECK (
        twin_type IN ('patient','tumor','cell_line','pathway','organ','workflow','process','population','other')
    ),
    twin_description TEXT NOT NULL,
    intended_use TEXT NOT NULL,
    risk_classification TEXT NOT NULL CHECK (risk_classification IN ('low','medium','high','critical')),
    owner TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','under_review','approved','active','retired','rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.twin_models (
    twin_model_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_twin_id UUID NOT NULL REFERENCES container_governance.digital_twins(digital_twin_id),
    model_name TEXT NOT NULL,
    model_version TEXT NOT NULL,
    model_description TEXT NOT NULL,
    source_entity_type TEXT,
    source_entity_id TEXT,
    artifact_uri TEXT,
    artifact_sha256 TEXT,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    UNIQUE(digital_twin_id, model_name, model_version)
);

CREATE TABLE IF NOT EXISTS container_governance.twin_versions (
    twin_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_twin_id UUID NOT NULL REFERENCES container_governance.digital_twins(digital_twin_id),
    twin_version TEXT NOT NULL,
    model_snapshot_uri TEXT,
    model_snapshot_sha256 TEXT,
    data_snapshot_uri TEXT,
    data_snapshot_sha256 TEXT,
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(digital_twin_id, twin_version)
);

CREATE TABLE IF NOT EXISTS container_governance.twin_simulations (
    twin_simulation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_twin_id UUID NOT NULL REFERENCES container_governance.digital_twins(digital_twin_id),
    twin_version_id UUID REFERENCES container_governance.twin_versions(twin_version_id),
    simulation_name TEXT NOT NULL,
    simulation_description TEXT NOT NULL,
    execution_run_id UUID REFERENCES container_governance.execution_runs(execution_run_id),
    simulation_parameters JSONB NOT NULL DEFAULT '{}',
    simulation_status TEXT NOT NULL DEFAULT 'planned'
        CHECK (simulation_status IN ('planned','running','completed','failed','reviewed','rejected')),
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.twin_validations (
    twin_validation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_twin_id UUID NOT NULL REFERENCES container_governance.digital_twins(digital_twin_id),
    twin_version_id UUID REFERENCES container_governance.twin_versions(twin_version_id),
    validation_type TEXT NOT NULL CHECK (
        validation_type IN ('face_validity','internal_validity','external_validity','clinical_validity','technical_validation','bias_review','safety_review')
    ),
    validation_status TEXT NOT NULL CHECK (validation_status IN ('pass','fail','warning','not_applicable')),
    validation_summary TEXT NOT NULL,
    executed_by TEXT NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.twin_risk_assessments (
    twin_risk_assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_twin_id UUID NOT NULL REFERENCES container_governance.digital_twins(digital_twin_id),
    risk_summary TEXT NOT NULL,
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high','critical')),
    mitigation_plan TEXT NOT NULL,
    assessed_by TEXT NOT NULL,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    next_review_due_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.twin_governance_reviews (
    twin_governance_review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_twin_id UUID NOT NULL REFERENCES container_governance.digital_twins(digital_twin_id),
    reviewer_identity TEXT NOT NULL,
    reviewer_role TEXT NOT NULL,
    review_decision TEXT NOT NULL CHECK (review_decision IN ('approved','rejected','needs_revision')),
    review_comments TEXT NOT NULL,
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW container_governance.v_digital_twin_lineage AS
SELECT
    dt.twin_code,
    dt.twin_name,
    dt.twin_type,
    dt.intended_use,
    tm.model_name,
    tm.model_version,
    tv.twin_version,
    ts.simulation_name,
    ts.execution_run_id,
    er.image_id,
    ci.image_name,
    ci.image_version
FROM container_governance.digital_twins dt
LEFT JOIN container_governance.twin_models tm ON tm.digital_twin_id = dt.digital_twin_id
LEFT JOIN container_governance.twin_versions tv ON tv.digital_twin_id = dt.digital_twin_id
LEFT JOIN container_governance.twin_simulations ts ON ts.digital_twin_id = dt.digital_twin_id
LEFT JOIN container_governance.execution_runs er ON er.execution_run_id = ts.execution_run_id
LEFT JOIN container_governance.container_images ci ON ci.image_id = er.image_id;

CREATE INDEX IF NOT EXISTS idx_digital_twins_type ON container_governance.digital_twins(twin_type);
CREATE INDEX IF NOT EXISTS idx_twin_simulations_run ON container_governance.twin_simulations(execution_run_id);
CREATE INDEX IF NOT EXISTS idx_twin_validations_twin ON container_governance.twin_validations(digital_twin_id);

COMMIT;
