-- ============================================================================
-- BioDiscoveryAI Global Identity Framework
-- Migration: V059__global_identity_framework.sql
-- Purpose:
--   Provide enterprise-wide object identifiers, namespaces, ID generation rules,
--   identity reservations, and cross-system identity mapping.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_kernel;

CREATE SEQUENCE IF NOT EXISTS governance_kernel.enterprise_object_sequence START 1;

CREATE TABLE IF NOT EXISTS governance_kernel.identity_namespaces (
    namespace_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace_code          TEXT NOT NULL UNIQUE,
    namespace_name          TEXT NOT NULL,
    namespace_description   TEXT NOT NULL,
    id_prefix               TEXT NOT NULL UNIQUE,
    padding_length          INT NOT NULL DEFAULT 6 CHECK (padding_length BETWEEN 3 AND 20),
    owner                   TEXT NOT NULL,
    active                  BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_kernel.identity_allocations (
    identity_allocation_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace_id            UUID NOT NULL REFERENCES governance_kernel.identity_namespaces(namespace_id),
    enterprise_object_id    TEXT NOT NULL UNIQUE,
    allocated_to_entity_id  UUID REFERENCES governance_kernel.governance_entities(entity_id),
    allocation_status       TEXT NOT NULL DEFAULT 'reserved'
        CHECK (allocation_status IN ('reserved','assigned','retired','voided')),
    allocated_by            TEXT NOT NULL DEFAULT current_user,
    allocated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_kernel.external_identity_mappings (
    external_identity_mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id                UUID NOT NULL REFERENCES governance_kernel.governance_entities(entity_id),
    external_system          TEXT NOT NULL,
    external_object_type     TEXT NOT NULL,
    external_object_id       TEXT NOT NULL,
    mapping_status           TEXT NOT NULL DEFAULT 'active'
        CHECK (mapping_status IN ('active','superseded','retired','invalid')),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(external_system, external_object_type, external_object_id)
);

CREATE OR REPLACE FUNCTION governance_kernel.allocate_enterprise_object_id(p_namespace_code TEXT)
RETURNS TEXT AS $$
DECLARE
    ns RECORD;
    next_num BIGINT;
    new_id TEXT;
BEGIN
    SELECT *
    INTO ns
    FROM governance_kernel.identity_namespaces
    WHERE namespace_code = p_namespace_code
      AND active = true;

    IF ns.namespace_id IS NULL THEN
        RAISE EXCEPTION 'Identity namespace % does not exist or is inactive', p_namespace_code;
    END IF;

    next_num := nextval('governance_kernel.enterprise_object_sequence');
    new_id := ns.id_prefix || '-' || lpad(next_num::TEXT, ns.padding_length, '0');

    INSERT INTO governance_kernel.identity_allocations (
        namespace_id, enterprise_object_id, allocation_status
    )
    VALUES (ns.namespace_id, new_id, 'reserved');

    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

INSERT INTO governance_kernel.identity_namespaces (
    namespace_code, namespace_name, namespace_description, id_prefix, owner
)
VALUES
('BDAI_CONTAINER','BioDiscoveryAI Container Objects','Global IDs for container images, packages, builds, and runtime artifacts.','BDAI-CONT','Platform Architecture'),
('BDAI_RISK','BioDiscoveryAI Risk Objects','Global IDs for enterprise and operational risks.','BDAI-RISK','Enterprise Risk'),
('BDAI_VENDOR','BioDiscoveryAI Vendor Objects','Global IDs for vendor and third-party records.','BDAI-VEND','Vendor Governance'),
('BDAI_STUDY','BioDiscoveryAI Scientific Study Objects','Global IDs for scientific studies and protocols.','BDAI-STUDY','Scientific Governance'),
('BDAI_MODEL','BioDiscoveryAI Model Objects','Global IDs for AI/ML models and model versions.','BDAI-MODEL','AI Governance'),
('BDAI_DATA','BioDiscoveryAI Data Objects','Global IDs for data assets and master data objects.','BDAI-DATA','Data Governance'),
('BDAI_TWIN','BioDiscoveryAI Digital Twin Objects','Global IDs for digital twins and simulations.','BDAI-TWIN','Digital Twin Governance'),
('BDAI_SUBMISSION','BioDiscoveryAI Regulatory Submission Objects','Global IDs for regulatory submissions and evidence packets.','BDAI-SUB','Regulatory Governance')
ON CONFLICT (namespace_code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_identity_allocations_entity
ON governance_kernel.identity_allocations(allocated_to_entity_id);

CREATE INDEX IF NOT EXISTS idx_external_identity_mappings_entity
ON governance_kernel.external_identity_mappings(entity_id);

COMMIT;
