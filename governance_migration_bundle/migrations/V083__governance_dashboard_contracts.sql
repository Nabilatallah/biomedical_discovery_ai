-- ============================================================================
-- BioDiscoveryAI Governance Dashboard Contracts
-- Migration: V089__governance_dashboard_contracts.sql
-- Purpose:
--   Define dashboard contracts, tiles, metrics, filters, data sources,
--   access policies, and executive/audit dashboards for governance visibility.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_contracts;

CREATE TABLE IF NOT EXISTS governance_contracts.dashboard_catalog (
    dashboard_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dashboard_code TEXT NOT NULL UNIQUE,
    dashboard_name TEXT NOT NULL,
    dashboard_description TEXT NOT NULL,
    dashboard_type TEXT NOT NULL CHECK (
        dashboard_type IN ('executive','audit','security','compliance','devsecops','scientific','regulatory','operations','financial','risk','other')
    ),
    owner TEXT NOT NULL,
    audience TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','deprecated','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.dashboard_data_sources (
    dashboard_data_source_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dashboard_id UUID NOT NULL REFERENCES governance_contracts.dashboard_catalog(dashboard_id),
    source_name TEXT NOT NULL,
    source_description TEXT NOT NULL,
    source_schema TEXT NOT NULL,
    source_view_or_table TEXT NOT NULL,
    refresh_frequency TEXT NOT NULL,
    owner TEXT NOT NULL,
    UNIQUE(dashboard_id, source_name)
);

CREATE TABLE IF NOT EXISTS governance_contracts.dashboard_metrics (
    dashboard_metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dashboard_id UUID NOT NULL REFERENCES governance_contracts.dashboard_catalog(dashboard_id),
    metric_code TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    metric_description TEXT NOT NULL,
    metric_query TEXT NOT NULL,
    metric_unit TEXT,
    threshold_green TEXT,
    threshold_yellow TEXT,
    threshold_red TEXT,
    owner TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(dashboard_id, metric_code)
);

CREATE TABLE IF NOT EXISTS governance_contracts.dashboard_tiles (
    dashboard_tile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dashboard_id UUID NOT NULL REFERENCES governance_contracts.dashboard_catalog(dashboard_id),
    tile_name TEXT NOT NULL,
    tile_description TEXT NOT NULL,
    tile_type TEXT NOT NULL CHECK (tile_type IN ('table','kpi','chart','trend','heatmap','timeline','status','text')),
    dashboard_metric_id UUID REFERENCES governance_contracts.dashboard_metrics(dashboard_metric_id),
    display_order INT NOT NULL DEFAULT 1,
    configuration JSONB NOT NULL DEFAULT '{}',
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(dashboard_id, tile_name)
);

CREATE TABLE IF NOT EXISTS governance_contracts.dashboard_access_policies (
    dashboard_access_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dashboard_id UUID NOT NULL REFERENCES governance_contracts.dashboard_catalog(dashboard_id),
    allowed_roles TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    restricted_fields TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    export_allowed BOOLEAN NOT NULL DEFAULT false,
    audit_access BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(dashboard_id)
);

INSERT INTO governance_contracts.dashboard_catalog (
    dashboard_code, dashboard_name, dashboard_description, dashboard_type, owner, audience, approval_status, approved_by, approved_at
)
VALUES
('EXEC_GOV_OVERVIEW','Executive Governance Overview','Executive view of governance readiness, risk, compliance, release posture, and incidents.','executive','Executive Governance','Executive Leadership','approved','Architecture Review Board',now()),
('AUDIT_READINESS','Audit Readiness Dashboard','Audit and inspection readiness across evidence, validation, signatures, controls, and CAPA.','audit','Compliance','Auditors and Compliance','approved','Architecture Review Board',now()),
('DEVSECOPS_READINESS','DevSecOps Readiness Dashboard','Container, package, policy, vulnerability, SBOM, signature, and release-readiness dashboard.','devsecops','Security Engineering','Platform/Security','approved','Architecture Review Board',now())
ON CONFLICT (dashboard_code) DO NOTHING;

COMMIT;
