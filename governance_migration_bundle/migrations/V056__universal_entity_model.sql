-- ============================================================================
-- BioDiscoveryAI Universal Entity Model
-- Migration: V058__universal_entity_model.sql
-- Purpose:
--   Establish a universal governance entity layer so all domains can register
--   objects consistently: containers, packages, vendors, risks, studies, models,
--   data assets, twins, submissions, policies, evidence, people, and decisions.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_kernel;

CREATE TABLE IF NOT EXISTS governance_kernel.entity_types (
    entity_type_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type_code        TEXT NOT NULL UNIQUE,
    entity_type_name        TEXT NOT NULL,
    entity_type_description TEXT NOT NULL,
    owning_domain           TEXT NOT NULL,
    lifecycle_model         TEXT NOT NULL DEFAULT 'standard',
    regulated               BOOLEAN NOT NULL DEFAULT false,
    active                  BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_kernel.governance_entities (
    entity_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type_id          UUID NOT NULL REFERENCES governance_kernel.entity_types(entity_type_id),
    enterprise_object_id    TEXT NOT NULL UNIQUE,
    canonical_name          TEXT NOT NULL,
    display_name            TEXT NOT NULL,
    description             TEXT,
    source_schema           TEXT,
    source_table            TEXT,
    source_primary_key      TEXT,
    owner                   TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','active','under_review','approved','rejected','deprecated','retired','archived')),
    criticality             TEXT NOT NULL DEFAULT 'medium'
        CHECK (criticality IN ('low','medium','high','critical')),
    regulated_scope         TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_by              TEXT NOT NULL DEFAULT current_user,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(source_schema, source_table, source_primary_key)
);

CREATE TABLE IF NOT EXISTS governance_kernel.entity_attributes (
    entity_attribute_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id               UUID NOT NULL REFERENCES governance_kernel.governance_entities(entity_id),
    attribute_name          TEXT NOT NULL,
    attribute_value         TEXT,
    attribute_json          JSONB,
    attribute_type          TEXT NOT NULL DEFAULT 'text'
        CHECK (attribute_type IN ('text','number','boolean','date','timestamp','json','uri','hash','enum')),
    source                  TEXT NOT NULL DEFAULT 'manual',
    effective_from          TIMESTAMPTZ NOT NULL DEFAULT now(),
    effective_to            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(entity_id, attribute_name, effective_from)
);

CREATE TABLE IF NOT EXISTS governance_kernel.entity_aliases (
    entity_alias_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id               UUID NOT NULL REFERENCES governance_kernel.governance_entities(entity_id),
    alias_type              TEXT NOT NULL CHECK (alias_type IN ('legacy_id','external_id','registry_id','display_alias','system_id')),
    alias_value             TEXT NOT NULL,
    alias_source            TEXT NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(alias_type, alias_value)
);

CREATE OR REPLACE FUNCTION governance_kernel.touch_entity_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_touch_governance_entities ON governance_kernel.governance_entities;
CREATE TRIGGER trg_touch_governance_entities
BEFORE UPDATE ON governance_kernel.governance_entities
FOR EACH ROW
EXECUTE FUNCTION governance_kernel.touch_entity_updated_at();

CREATE INDEX IF NOT EXISTS idx_governance_entities_type
ON governance_kernel.governance_entities(entity_type_id);

CREATE INDEX IF NOT EXISTS idx_governance_entities_status
ON governance_kernel.governance_entities(status);

CREATE INDEX IF NOT EXISTS idx_governance_entities_source
ON governance_kernel.governance_entities(source_schema, source_table, source_primary_key);

INSERT INTO governance_kernel.entity_types (
    entity_type_code, entity_type_name, entity_type_description, owning_domain, regulated
)
VALUES
('CONTAINER_IMAGE','Container Image','Governed Docker/Apptainer container image.','container_governance',true),
('PACKAGE','Software Package','Approved software package or dependency.','container_governance',true),
('VENDOR','Vendor','Third-party supplier, platform, SaaS, cloud, model provider, or tooling vendor.','vendor_governance',true),
('RISK','Enterprise Risk','Governed enterprise, operational, cyber, scientific, or compliance risk.','risk_governance',true),
('STUDY','Scientific Study','Scientific, translational, or regulated research study.','scientific_governance',true),
('MODEL','AI/ML Model','AI, ML, statistical, or rules-based model.','ai_governance',true),
('DATA_ASSET','Data Asset','Dataset, data product, reference data, master data, or regulated data asset.','data_governance',true),
('DIGITAL_TWIN','Digital Twin','Patient, tumor, pathway, workflow, process, or population twin.','digital_twin_governance',true),
('SUBMISSION','Regulatory Submission','IND, NDA, BLA, EMA, or inspection submission package.','regulatory_governance',true),
('PERSON','Person','Governed human actor, approver, reviewer, validator, auditor, or owner.','human_governance',true)
ON CONFLICT (entity_type_code) DO NOTHING;

COMMIT;
