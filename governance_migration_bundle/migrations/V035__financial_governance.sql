-- ============================================================================
-- BioDiscoveryAI Financial Governance
-- Migration: V037__financial_governance.sql
-- Purpose:
--   Cost centers, budgets, project funding, cloud/HPC/container cost attribution,
--   chargeback/showback, forecasts, ROI tracking, and financial controls.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.cost_centers (
    cost_center_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cost_center_code TEXT NOT NULL UNIQUE,
    cost_center_name TEXT NOT NULL,
    owner TEXT NOT NULL,
    business_unit TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.governance_projects (
    project_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_code TEXT NOT NULL UNIQUE,
    project_name TEXT NOT NULL,
    project_description TEXT NOT NULL,
    cost_center_id UUID REFERENCES container_governance.cost_centers(cost_center_id),
    sponsor TEXT NOT NULL,
    owner TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('planned','active','paused','completed','cancelled','archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.budgets (
    budget_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES container_governance.governance_projects(project_id),
    cost_center_id UUID REFERENCES container_governance.cost_centers(cost_center_id),
    fiscal_year INT NOT NULL,
    budget_amount NUMERIC(14,2) NOT NULL CHECK (budget_amount >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    approved_by TEXT NOT NULL,
    approved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(project_id, cost_center_id, fiscal_year)
);

CREATE TABLE IF NOT EXISTS container_governance.cost_records (
    cost_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES container_governance.governance_projects(project_id),
    cost_center_id UUID REFERENCES container_governance.cost_centers(cost_center_id),
    related_entity_type TEXT,
    related_entity_id TEXT,
    cost_category TEXT NOT NULL CHECK (
        cost_category IN ('cloud_compute','hpc_compute','storage','registry','license','vendor','labor','security_tool','other')
    ),
    amount NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    usage_start TIMESTAMPTZ,
    usage_end TIMESTAMPTZ,
    source_system TEXT NOT NULL,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.chargeback_records (
    chargeback_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cost_record_id UUID NOT NULL REFERENCES container_governance.cost_records(cost_record_id),
    charged_to_cost_center_id UUID NOT NULL REFERENCES container_governance.cost_centers(cost_center_id),
    allocation_percentage NUMERIC(5,2) NOT NULL CHECK (allocation_percentage > 0 AND allocation_percentage <= 100),
    chargeback_amount NUMERIC(14,2) NOT NULL CHECK (chargeback_amount >= 0),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.roi_records (
    roi_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES container_governance.governance_projects(project_id),
    benefit_type TEXT NOT NULL CHECK (benefit_type IN ('cost_avoidance','revenue_enablement','time_saved','risk_reduction','quality_improvement','other')),
    benefit_description TEXT NOT NULL,
    estimated_value NUMERIC(14,2),
    realized_value NUMERIC(14,2),
    currency TEXT NOT NULL DEFAULT 'USD',
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    recorded_by TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW container_governance.v_project_financial_summary AS
SELECT
    gp.project_code,
    gp.project_name,
    cc.cost_center_code,
    b.fiscal_year,
    b.budget_amount,
    COALESCE(SUM(cr.amount), 0) AS actual_cost,
    b.budget_amount - COALESCE(SUM(cr.amount), 0) AS remaining_budget
FROM container_governance.governance_projects gp
LEFT JOIN container_governance.cost_centers cc ON cc.cost_center_id = gp.cost_center_id
LEFT JOIN container_governance.budgets b ON b.project_id = gp.project_id
LEFT JOIN container_governance.cost_records cr ON cr.project_id = gp.project_id
GROUP BY gp.project_code, gp.project_name, cc.cost_center_code, b.fiscal_year, b.budget_amount;

CREATE INDEX IF NOT EXISTS idx_cost_records_project ON container_governance.cost_records(project_id);
CREATE INDEX IF NOT EXISTS idx_cost_records_entity ON container_governance.cost_records(related_entity_type, related_entity_id);

COMMIT;
