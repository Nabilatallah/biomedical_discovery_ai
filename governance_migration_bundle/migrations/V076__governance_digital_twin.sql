-- ============================================================================
-- BioDiscoveryAI Governance Digital Twin
-- Migration: V082__governance_digital_twin.sql
-- Purpose:
--   Create a digital twin of the governance system itself to simulate policy
--   changes, risk shifts, vendor failures, inspection scenarios, workflow
--   bottlenecks, and operational resilience.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_twin;

CREATE TABLE IF NOT EXISTS governance_twin.governance_twin_models (
    governance_twin_model_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_code TEXT NOT NULL UNIQUE,
    model_name TEXT NOT NULL,
    model_description TEXT NOT NULL,
    model_scope TEXT NOT NULL,
    model_version TEXT NOT NULL,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_twin.governance_twin_snapshots (
    governance_twin_snapshot_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_twin_model_id UUID NOT NULL REFERENCES governance_twin.governance_twin_models(governance_twin_model_id),
    snapshot_name TEXT NOT NULL,
    snapshot_time TIMESTAMPTZ NOT NULL,
    snapshot_uri TEXT,
    snapshot_sha256 TEXT,
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(governance_twin_model_id, snapshot_name, snapshot_time)
);

CREATE TABLE IF NOT EXISTS governance_twin.governance_twin_scenarios (
    governance_twin_scenario_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_twin_model_id UUID NOT NULL REFERENCES governance_twin.governance_twin_models(governance_twin_model_id),
    scenario_name TEXT NOT NULL,
    scenario_description TEXT NOT NULL,
    scenario_type TEXT NOT NULL CHECK (
        scenario_type IN ('vendor_failure','registry_compromise','policy_change','inspection','capacity_stress','workflow_bottleneck','risk_escalation','other')
    ),
    assumptions JSONB NOT NULL DEFAULT '{}',
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_twin.governance_twin_simulation_runs (
    governance_twin_simulation_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_twin_scenario_id UUID NOT NULL REFERENCES governance_twin.governance_twin_scenarios(governance_twin_scenario_id),
    run_status TEXT NOT NULL DEFAULT 'started'
        CHECK (run_status IN ('started','completed','failed','cancelled')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    result_summary TEXT,
    result_payload JSONB NOT NULL DEFAULT '{}',
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_twin.governance_twin_findings (
    governance_twin_finding_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_twin_simulation_run_id UUID NOT NULL REFERENCES governance_twin.governance_twin_simulation_runs(governance_twin_simulation_run_id),
    finding_title TEXT NOT NULL,
    finding_description TEXT NOT NULL,
    finding_severity TEXT NOT NULL CHECK (finding_severity IN ('low','medium','high','critical')),
    recommended_action TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','accepted','remediated','rejected','closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW governance_twin.v_governance_twin_findings AS
SELECT
    gtm.model_code,
    gts.scenario_name,
    gts.scenario_type,
    gtsr.run_status,
    gtf.finding_title,
    gtf.finding_severity,
    gtf.recommended_action,
    gtf.status
FROM governance_twin.governance_twin_findings gtf
JOIN governance_twin.governance_twin_simulation_runs gtsr ON gtsr.governance_twin_simulation_run_id = gtf.governance_twin_simulation_run_id
JOIN governance_twin.governance_twin_scenarios gts ON gts.governance_twin_scenario_id = gtsr.governance_twin_scenario_id
JOIN governance_twin.governance_twin_models gtm ON gtm.governance_twin_model_id = gts.governance_twin_model_id;

COMMIT;
