-- ============================================================================
-- BioDiscoveryAI Vendor Risk Management
-- Migration: V034__vendor_risk_management.sql
-- Purpose:
--   Vendor inventory, services, data access, assessments, certifications,
--   contracts, SOC reports, penetration tests, vendor incidents, risk scoring,
--   offboarding, and linkage to container/software supply chain.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.vendors (
    vendor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_name TEXT NOT NULL UNIQUE,
    vendor_type TEXT NOT NULL CHECK (
        vendor_type IN ('cloud','ai_model_provider','code_repository','container_registry','security_tool','data_provider','saas','consultant','other')
    ),
    vendor_description TEXT NOT NULL,
    criticality TEXT NOT NULL CHECK (criticality IN ('low','medium','high','critical')),
    data_access_level TEXT NOT NULL CHECK (data_access_level IN ('none','metadata','confidential','pii','phi','regulated_research')),
    owner TEXT NOT NULL,
    onboarding_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (onboarding_status IN ('pending','approved','rejected','offboarding','offboarded')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.vendor_services (
    vendor_service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES container_governance.vendors(vendor_id),
    service_name TEXT NOT NULL,
    service_description TEXT NOT NULL,
    service_category TEXT NOT NULL,
    used_by_entity_type TEXT,
    used_by_entity_id TEXT,
    sla_summary TEXT,
    data_processed TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(vendor_id, service_name)
);

CREATE TABLE IF NOT EXISTS container_governance.vendor_assessments (
    vendor_assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES container_governance.vendors(vendor_id),
    assessment_type TEXT NOT NULL CHECK (
        assessment_type IN ('initial_due_diligence','annual_review','security_review','privacy_review','quality_review','financial_review','incident_review')
    ),
    assessment_status TEXT NOT NULL CHECK (assessment_status IN ('pass','fail','conditional','in_progress')),
    risk_rating TEXT NOT NULL CHECK (risk_rating IN ('low','medium','high','critical')),
    assessment_summary TEXT NOT NULL,
    assessed_by TEXT NOT NULL,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    next_assessment_due_at TIMESTAMPTZ,
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.vendor_certifications (
    vendor_certification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES container_governance.vendors(vendor_id),
    certification_type TEXT NOT NULL CHECK (
        certification_type IN ('soc2_type1','soc2_type2','iso27001','iso27701','hipaa_baa','gxp_quality_agreement','pen_test','other')
    ),
    certification_scope TEXT NOT NULL,
    issued_at DATE,
    expires_at DATE,
    reviewed_by TEXT,
    review_status TEXT NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending','approved','rejected','expired')),
    evidence_uri TEXT NOT NULL,
    evidence_sha256 TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS container_governance.vendor_contracts (
    vendor_contract_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES container_governance.vendors(vendor_id),
    contract_type TEXT NOT NULL CHECK (contract_type IN ('msa','dpa','baa','quality_agreement','sla','order_form','other')),
    contract_summary TEXT NOT NULL,
    effective_date DATE NOT NULL,
    expiration_date DATE,
    renewal_terms TEXT,
    owner TEXT NOT NULL,
    legal_approved_by TEXT,
    legal_approved_at TIMESTAMPTZ,
    artifact_uri TEXT NOT NULL,
    artifact_sha256 TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS container_governance.vendor_incidents (
    vendor_incident_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES container_governance.vendors(vendor_id),
    incident_id UUID REFERENCES container_governance.security_incidents(incident_id),
    incident_summary TEXT NOT NULL,
    impact_assessment TEXT NOT NULL,
    notification_received_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','monitoring','resolved','closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.vendor_offboarding_records (
    vendor_offboarding_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT NULL REFERENCES container_governance.vendors(vendor_id),
    offboarding_reason TEXT NOT NULL,
    data_return_required BOOLEAN NOT NULL DEFAULT false,
    data_deletion_required BOOLEAN NOT NULL DEFAULT true,
    access_revocation_summary TEXT NOT NULL,
    offboarded_by TEXT NOT NULL,
    offboarded_at TIMESTAMPTZ,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','in_progress','completed','cancelled'))
);

CREATE OR REPLACE VIEW container_governance.v_vendor_risk_status AS
SELECT
    v.vendor_id,
    v.vendor_name,
    v.vendor_type,
    v.criticality,
    v.data_access_level,
    v.onboarding_status,
    MAX(va.assessed_at) AS last_assessed_at,
    MAX(va.next_assessment_due_at) AS next_assessment_due_at,
    COUNT(vc.vendor_certification_id) FILTER (
        WHERE vc.expires_at IS NOT NULL AND vc.expires_at < CURRENT_DATE
    ) AS expired_certifications,
    COUNT(vi.vendor_incident_id) FILTER (WHERE vi.status IN ('open','monitoring')) AS open_vendor_incidents
FROM container_governance.vendors v
LEFT JOIN container_governance.vendor_assessments va ON va.vendor_id = v.vendor_id
LEFT JOIN container_governance.vendor_certifications vc ON vc.vendor_id = v.vendor_id
LEFT JOIN container_governance.vendor_incidents vi ON vi.vendor_id = v.vendor_id
GROUP BY v.vendor_id, v.vendor_name, v.vendor_type, v.criticality, v.data_access_level, v.onboarding_status;

CREATE INDEX IF NOT EXISTS idx_vendors_type ON container_governance.vendors(vendor_type);
CREATE INDEX IF NOT EXISTS idx_vendor_assessments_vendor ON container_governance.vendor_assessments(vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_certifications_vendor ON container_governance.vendor_certifications(vendor_id);

COMMIT;
