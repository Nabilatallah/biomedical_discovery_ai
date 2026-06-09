-- ============================================================================
-- BioDiscoveryAI Multi-Enterprise Federation
-- Migration: V078__multi_enterprise_federation.sql
-- Purpose:
--   Enable governed federation across enterprise partners, CROs, universities,
--   vendors, regulators, cloud tenants, and research collaborators.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_federation;

CREATE TABLE IF NOT EXISTS governance_federation.federated_organizations (
    federated_organization_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_code TEXT NOT NULL UNIQUE,
    organization_name TEXT NOT NULL,
    organization_type TEXT NOT NULL CHECK (
        organization_type IN ('internal','partner','cro','university','vendor','regulator','cloud_provider','other')
    ),
    trust_level TEXT NOT NULL CHECK (trust_level IN ('none','limited','standard','high','regulated')),
    data_sharing_allowed BOOLEAN NOT NULL DEFAULT false,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','suspended','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_federation.federation_agreements (
    federation_agreement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    federated_organization_id UUID NOT NULL REFERENCES governance_federation.federated_organizations(federated_organization_id),
    agreement_type TEXT NOT NULL CHECK (agreement_type IN ('data_sharing','compute_sharing','model_sharing','audit_sharing','regulatory_collaboration','other')),
    agreement_summary TEXT NOT NULL,
    effective_from DATE NOT NULL,
    expires_on DATE,
    artifact_uri TEXT NOT NULL,
    artifact_sha256 TEXT NOT NULL,
    approved_by TEXT NOT NULL,
    approved_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_federation.federated_identity_mappings (
    federated_identity_mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    federated_organization_id UUID NOT NULL REFERENCES governance_federation.federated_organizations(federated_organization_id),
    local_entity_id UUID,
    local_enterprise_object_id TEXT,
    remote_object_type TEXT NOT NULL,
    remote_object_id TEXT NOT NULL,
    mapping_status TEXT NOT NULL DEFAULT 'active'
        CHECK (mapping_status IN ('active','superseded','retired','revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(federated_organization_id, remote_object_type, remote_object_id)
);

CREATE TABLE IF NOT EXISTS governance_federation.federated_exchanges (
    federated_exchange_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    federated_organization_id UUID NOT NULL REFERENCES governance_federation.federated_organizations(federated_organization_id),
    exchange_type TEXT NOT NULL CHECK (exchange_type IN ('metadata','evidence','audit','model','data','policy','submission','other')),
    exchange_direction TEXT NOT NULL CHECK (exchange_direction IN ('inbound','outbound','bidirectional')),
    exchange_summary TEXT NOT NULL,
    payload_uri TEXT,
    payload_sha256 TEXT,
    exchanged_by TEXT NOT NULL,
    exchanged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    exchange_status TEXT NOT NULL DEFAULT 'completed'
        CHECK (exchange_status IN ('requested','approved','completed','failed','rejected'))
);

CREATE OR REPLACE VIEW governance_federation.v_federation_status AS
SELECT
    fo.organization_code,
    fo.organization_name,
    fo.organization_type,
    fo.trust_level,
    fo.approval_status,
    COUNT(fa.federation_agreement_id) AS agreement_count,
    COUNT(fe.federated_exchange_id) AS exchange_count
FROM governance_federation.federated_organizations fo
LEFT JOIN governance_federation.federation_agreements fa ON fa.federated_organization_id = fo.federated_organization_id
LEFT JOIN governance_federation.federated_exchanges fe ON fe.federated_organization_id = fo.federated_organization_id
GROUP BY fo.organization_code, fo.organization_name, fo.organization_type, fo.trust_level, fo.approval_status;

COMMIT;
