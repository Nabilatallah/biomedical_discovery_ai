-- ============================================================================
-- BioDiscoveryAI Enterprise Risk Management
-- Migration: V033__enterprise_risk_management.sql
-- Purpose:
--   Enterprise risk taxonomy, risk register, scoring, heatmaps, treatments,
--   KRIs, risk appetite, executive reviews, and linkage to containers,
--   vendors, data, AI, scientific studies, and digital twins.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.risk_taxonomies (
    risk_taxonomy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    taxonomy_name TEXT NOT NULL UNIQUE,
    taxonomy_version TEXT NOT NULL,
    taxonomy_description TEXT NOT NULL,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.risk_categories (
    risk_category_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_taxonomy_id UUID NOT NULL REFERENCES container_governance.risk_taxonomies(risk_taxonomy_id),
    category_code TEXT NOT NULL,
    category_name TEXT NOT NULL,
    category_description TEXT NOT NULL,
    parent_category_id UUID REFERENCES container_governance.risk_categories(risk_category_id),
    UNIQUE(risk_taxonomy_id, category_code)
);

CREATE TABLE IF NOT EXISTS container_governance.enterprise_risks (
    enterprise_risk_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    risk_number TEXT NOT NULL UNIQUE,
    risk_title TEXT NOT NULL,
    risk_description TEXT NOT NULL,
    risk_category_id UUID REFERENCES container_governance.risk_categories(risk_category_id),
    related_entity_type TEXT,
    related_entity_id TEXT,
    inherent_likelihood INT NOT NULL CHECK (inherent_likelihood BETWEEN 1 AND 5),
    inherent_impact INT NOT NULL CHECK (inherent_impact BETWEEN 1 AND 5),
    residual_likelihood INT CHECK (residual_likelihood BETWEEN 1 AND 5),
    residual_impact INT CHECK (residual_impact BETWEEN 1 AND 5),
    risk_owner TEXT NOT NULL,
    risk_status TEXT NOT NULL DEFAULT 'open'
        CHECK (risk_status IN ('open','monitoring','treated','accepted','transferred','closed','retired')),
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_reviewed_at TIMESTAMPTZ,
    next_review_due_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.risk_treatments (
    risk_treatment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enterprise_risk_id UUID NOT NULL REFERENCES container_governance.enterprise_risks(enterprise_risk_id),
    treatment_type TEXT NOT NULL CHECK (treatment_type IN ('mitigate','accept','transfer','avoid','monitor')),
    treatment_plan TEXT NOT NULL,
    compensating_controls TEXT,
    owner TEXT NOT NULL,
    due_date DATE,
    status TEXT NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned','in_progress','implemented','verified','cancelled')),
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.key_risk_indicators (
    kri_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enterprise_risk_id UUID NOT NULL REFERENCES container_governance.enterprise_risks(enterprise_risk_id),
    kri_name TEXT NOT NULL,
    kri_description TEXT NOT NULL,
    measurement_method TEXT NOT NULL,
    threshold_green NUMERIC,
    threshold_yellow NUMERIC,
    threshold_red NUMERIC,
    owner TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(enterprise_risk_id, kri_name)
);

CREATE TABLE IF NOT EXISTS container_governance.kri_measurements (
    kri_measurement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kri_id UUID NOT NULL REFERENCES container_governance.key_risk_indicators(kri_id),
    measured_value NUMERIC NOT NULL,
    measurement_status TEXT NOT NULL CHECK (measurement_status IN ('green','yellow','red','unknown')),
    measured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    measured_by TEXT NOT NULL,
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.risk_appetite_statements (
    risk_appetite_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appetite_name TEXT NOT NULL UNIQUE,
    appetite_description TEXT NOT NULL,
    applicable_scope TEXT NOT NULL,
    tolerance_statement TEXT NOT NULL,
    approved_by TEXT NOT NULL,
    approved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    review_frequency TEXT NOT NULL DEFAULT 'annual',
    active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS container_governance.risk_review_cycles (
    risk_review_cycle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_name TEXT NOT NULL,
    review_period_start DATE NOT NULL,
    review_period_end DATE NOT NULL,
    reviewed_by TEXT NOT NULL,
    review_summary TEXT NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('accepted','actions_required','escalated','closed')),
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW container_governance.v_enterprise_risk_heatmap AS
SELECT
    er.enterprise_risk_id,
    er.risk_number,
    er.risk_title,
    er.risk_owner,
    er.inherent_likelihood,
    er.inherent_impact,
    (er.inherent_likelihood * er.inherent_impact) AS inherent_score,
    er.residual_likelihood,
    er.residual_impact,
    COALESCE(er.residual_likelihood * er.residual_impact, er.inherent_likelihood * er.inherent_impact) AS residual_score,
    er.risk_status,
    er.next_review_due_at
FROM container_governance.enterprise_risks er;

CREATE INDEX IF NOT EXISTS idx_enterprise_risks_status ON container_governance.enterprise_risks(risk_status);
CREATE INDEX IF NOT EXISTS idx_enterprise_risks_entity ON container_governance.enterprise_risks(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_kri_measurements_kri ON container_governance.kri_measurements(kri_id);

COMMIT;
