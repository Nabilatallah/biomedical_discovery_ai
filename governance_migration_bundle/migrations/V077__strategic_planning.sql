-- ============================================================================
-- BioDiscoveryAI Strategic Planning
-- Migration: V083__strategic_planning.sql
-- Purpose:
--   Govern future-state planning: strategies, scenarios, roadmaps, objectives,
--   strategic options, forecasts, assumptions, investment themes, and execution
--   alignment across governance domains.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS strategic_governance;

CREATE TABLE IF NOT EXISTS strategic_governance.strategic_objectives (
    strategic_objective_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    objective_code TEXT NOT NULL UNIQUE,
    objective_title TEXT NOT NULL,
    objective_description TEXT NOT NULL,
    owner TEXT NOT NULL,
    time_horizon TEXT NOT NULL CHECK (time_horizon IN ('quarter','year','three_year','five_year','long_range')),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('draft','active','paused','completed','retired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS strategic_governance.strategic_scenarios (
    strategic_scenario_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scenario_name TEXT NOT NULL,
    scenario_description TEXT NOT NULL,
    scenario_horizon TEXT NOT NULL,
    assumptions JSONB NOT NULL DEFAULT '{}',
    risks JSONB NOT NULL DEFAULT '[]',
    opportunities JSONB NOT NULL DEFAULT '[]',
    owner TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS strategic_governance.roadmaps (
    roadmap_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    roadmap_name TEXT NOT NULL,
    roadmap_description TEXT NOT NULL,
    roadmap_scope TEXT NOT NULL,
    owner TEXT NOT NULL,
    start_date DATE,
    end_date DATE,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','approved','active','completed','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS strategic_governance.roadmap_items (
    roadmap_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    roadmap_id UUID NOT NULL REFERENCES strategic_governance.roadmaps(roadmap_id),
    strategic_objective_id UUID REFERENCES strategic_governance.strategic_objectives(strategic_objective_id),
    item_name TEXT NOT NULL,
    item_description TEXT NOT NULL,
    target_date DATE,
    priority TEXT NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('low','medium','high','critical')),
    status TEXT NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned','in_progress','done','blocked','cancelled')),
    related_entity_type TEXT,
    related_entity_id TEXT
);

CREATE TABLE IF NOT EXISTS strategic_governance.strategic_forecasts (
    strategic_forecast_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    forecast_name TEXT NOT NULL,
    forecast_description TEXT NOT NULL,
    forecast_metric TEXT NOT NULL,
    forecast_value NUMERIC,
    forecast_period_start DATE,
    forecast_period_end DATE,
    confidence_level TEXT CHECK (confidence_level IN ('low','medium','high')),
    generated_by TEXT NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE OR REPLACE VIEW strategic_governance.v_strategy_execution_alignment AS
SELECT
    so.objective_code,
    so.objective_title,
    r.roadmap_name,
    ri.item_name,
    ri.priority,
    ri.status,
    ri.target_date
FROM strategic_governance.strategic_objectives so
LEFT JOIN strategic_governance.roadmap_items ri ON ri.strategic_objective_id = so.strategic_objective_id
LEFT JOIN strategic_governance.roadmaps r ON r.roadmap_id = ri.roadmap_id;

COMMIT;
