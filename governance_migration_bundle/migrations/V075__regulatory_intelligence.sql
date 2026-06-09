-- ============================================================================
-- BioDiscoveryAI Regulatory Intelligence
-- Migration: V081__regulatory_intelligence.sql
-- Purpose:
--   Track regulatory sources, guidance documents, changes, impact assessments,
--   control updates, regulatory watchlists, and compliance action plans.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS regulatory_intelligence;

CREATE TABLE IF NOT EXISTS regulatory_intelligence.regulatory_sources (
    regulatory_source_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_code TEXT NOT NULL UNIQUE,
    source_name TEXT NOT NULL,
    jurisdiction TEXT NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('agency','standard_body','law','guidance_portal','industry_group','other')),
    source_url TEXT,
    owner TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS regulatory_intelligence.regulatory_documents (
    regulatory_document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    regulatory_source_id UUID NOT NULL REFERENCES regulatory_intelligence.regulatory_sources(regulatory_source_id),
    document_title TEXT NOT NULL,
    document_identifier TEXT,
    document_version TEXT,
    publication_date DATE,
    effective_date DATE,
    document_uri TEXT,
    document_sha256 TEXT,
    summary TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('draft','active','superseded','withdrawn','archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS regulatory_intelligence.regulatory_change_events (
    regulatory_change_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    regulatory_document_id UUID REFERENCES regulatory_intelligence.regulatory_documents(regulatory_document_id),
    change_title TEXT NOT NULL,
    change_summary TEXT NOT NULL,
    change_type TEXT NOT NULL CHECK (change_type IN ('new_guidance','revision','withdrawal','deadline','interpretation','enforcement_trend','other')),
    detected_by TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    impact_assessment_required BOOLEAN NOT NULL DEFAULT true,
    status TEXT NOT NULL DEFAULT 'detected'
        CHECK (status IN ('detected','under_review','assessed','action_required','closed'))
);

CREATE TABLE IF NOT EXISTS regulatory_intelligence.regulatory_impact_assessments (
    regulatory_impact_assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    regulatory_change_event_id UUID NOT NULL REFERENCES regulatory_intelligence.regulatory_change_events(regulatory_change_event_id),
    impacted_domain TEXT NOT NULL,
    impact_summary TEXT NOT NULL,
    impact_level TEXT NOT NULL CHECK (impact_level IN ('none','low','medium','high','critical')),
    required_action TEXT,
    owner TEXT NOT NULL,
    due_date DATE,
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','in_progress','completed','not_applicable','cancelled')),
    assessed_by TEXT NOT NULL,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS regulatory_intelligence.regulatory_action_plans (
    regulatory_action_plan_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    regulatory_impact_assessment_id UUID NOT NULL REFERENCES regulatory_intelligence.regulatory_impact_assessments(regulatory_impact_assessment_id),
    action_title TEXT NOT NULL,
    action_description TEXT NOT NULL,
    action_owner TEXT NOT NULL,
    due_date DATE NOT NULL,
    action_status TEXT NOT NULL DEFAULT 'open'
        CHECK (action_status IN ('open','in_progress','completed','blocked','cancelled')),
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW regulatory_intelligence.v_open_regulatory_actions AS
SELECT
    rs.source_name,
    rd.document_title,
    rce.change_title,
    ria.impacted_domain,
    ria.impact_level,
    rap.action_title,
    rap.action_owner,
    rap.due_date,
    rap.action_status
FROM regulatory_intelligence.regulatory_action_plans rap
JOIN regulatory_intelligence.regulatory_impact_assessments ria ON ria.regulatory_impact_assessment_id = rap.regulatory_impact_assessment_id
JOIN regulatory_intelligence.regulatory_change_events rce ON rce.regulatory_change_event_id = ria.regulatory_change_event_id
LEFT JOIN regulatory_intelligence.regulatory_documents rd ON rd.regulatory_document_id = rce.regulatory_document_id
LEFT JOIN regulatory_intelligence.regulatory_sources rs ON rs.regulatory_source_id = rd.regulatory_source_id
WHERE rap.action_status NOT IN ('completed','cancelled');

COMMIT;
