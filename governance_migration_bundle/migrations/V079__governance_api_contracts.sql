-- ============================================================================
-- BioDiscoveryAI Governance API Contracts
-- Migration: V085__governance_api_contracts.sql
-- Purpose:
--   Define stable API contracts for the governance platform so external tools,
--   services, CI/CD pipelines, dashboards, and automation agents interact
--   through versioned contracts instead of directly mutating core tables.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_contracts;

CREATE TABLE IF NOT EXISTS governance_contracts.api_services (
    api_service_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_code TEXT NOT NULL UNIQUE,
    service_name TEXT NOT NULL,
    service_description TEXT NOT NULL,
    service_owner TEXT NOT NULL,
    base_path TEXT NOT NULL,
    service_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (service_status IN ('draft','active','deprecated','retired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.api_contracts (
    api_contract_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_service_id UUID NOT NULL REFERENCES governance_contracts.api_services(api_service_id),
    contract_name TEXT NOT NULL,
    contract_version TEXT NOT NULL,
    contract_description TEXT NOT NULL,
    openapi_uri TEXT,
    openapi_sha256 TEXT,
    compatibility_policy TEXT NOT NULL DEFAULT 'backward_compatible'
        CHECK (compatibility_policy IN ('backward_compatible','breaking_allowed_with_approval','internal_only')),
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','deprecated','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(api_service_id, contract_name, contract_version)
);

CREATE TABLE IF NOT EXISTS governance_contracts.api_endpoints (
    api_endpoint_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_contract_id UUID NOT NULL REFERENCES governance_contracts.api_contracts(api_contract_id),
    http_method TEXT NOT NULL CHECK (http_method IN ('GET','POST','PUT','PATCH','DELETE')),
    endpoint_path TEXT NOT NULL,
    endpoint_name TEXT NOT NULL,
    endpoint_description TEXT NOT NULL,
    request_schema JSONB NOT NULL DEFAULT '{}',
    response_schema JSONB NOT NULL DEFAULT '{}',
    required_role TEXT,
    regulated_endpoint BOOLEAN NOT NULL DEFAULT true,
    audit_required BOOLEAN NOT NULL DEFAULT true,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(api_contract_id, http_method, endpoint_path)
);

CREATE TABLE IF NOT EXISTS governance_contracts.api_contract_tests (
    api_contract_test_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_endpoint_id UUID NOT NULL REFERENCES governance_contracts.api_endpoints(api_endpoint_id),
    test_name TEXT NOT NULL,
    test_description TEXT NOT NULL,
    expected_status_code INT NOT NULL,
    expected_result TEXT NOT NULL,
    test_status TEXT NOT NULL DEFAULT 'not_run'
        CHECK (test_status IN ('not_run','pass','fail','blocked')),
    last_run_at TIMESTAMPTZ,
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_contracts.api_access_policies (
    api_access_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_endpoint_id UUID NOT NULL REFERENCES governance_contracts.api_endpoints(api_endpoint_id),
    policy_name TEXT NOT NULL,
    policy_description TEXT NOT NULL,
    allowed_roles TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    rate_limit_per_minute INT,
    mfa_required BOOLEAN NOT NULL DEFAULT false,
    electronic_signature_required BOOLEAN NOT NULL DEFAULT false,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(api_endpoint_id, policy_name)
);

CREATE OR REPLACE VIEW governance_contracts.v_api_contract_readiness AS
SELECT
    s.service_code,
    s.service_name,
    c.contract_name,
    c.contract_version,
    c.approval_status,
    COUNT(e.api_endpoint_id) AS endpoint_count,
    COUNT(t.api_contract_test_id) FILTER (WHERE t.test_status = 'pass') AS passed_tests,
    COUNT(t.api_contract_test_id) FILTER (WHERE t.test_status = 'fail') AS failed_tests
FROM governance_contracts.api_services s
JOIN governance_contracts.api_contracts c ON c.api_service_id = s.api_service_id
LEFT JOIN governance_contracts.api_endpoints e ON e.api_contract_id = c.api_contract_id
LEFT JOIN governance_contracts.api_contract_tests t ON t.api_endpoint_id = e.api_endpoint_id
GROUP BY s.service_code, s.service_name, c.contract_name, c.contract_version, c.approval_status;

INSERT INTO governance_contracts.api_services (
    service_code, service_name, service_description, service_owner, base_path, service_status
)
VALUES
('GOVERNANCE_API','Governance API','Primary API for governed creation, approval, release, evidence, lineage, and audit operations.','Platform Engineering','/api/v1/governance','active'),
('EVIDENCE_API','Evidence API','API for registering and retrieving evidence, SBOMs, signatures, validation, and release packets.','Compliance Engineering','/api/v1/evidence','active'),
('LINEAGE_API','Lineage API','API for entity, relationship, event, and temporal lineage queries.','Architecture Governance','/api/v1/lineage','active')
ON CONFLICT (service_code) DO NOTHING;

COMMIT;
