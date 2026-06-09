-- ============================================================================
-- BioDiscoveryAI Metadata Registry
-- Migration: V061__metadata_registry.sql
-- Purpose:
--   Create an enterprise metadata registry for schemas, tables, columns,
--   controlled vocabularies, glossary terms, data definitions, and lineage.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_kernel;

CREATE TABLE IF NOT EXISTS governance_kernel.metadata_domains (
    metadata_domain_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_code             TEXT NOT NULL UNIQUE,
    domain_name             TEXT NOT NULL,
    domain_description      TEXT NOT NULL,
    owner                   TEXT NOT NULL,
    steward                 TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_kernel.metadata_objects (
    metadata_object_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metadata_domain_id      UUID REFERENCES governance_kernel.metadata_domains(metadata_domain_id),
    object_type             TEXT NOT NULL CHECK (
        object_type IN ('schema','table','view','column','function','trigger','policy','file','api','metric','glossary_term','controlled_vocabulary')
    ),
    object_schema           TEXT,
    object_name             TEXT NOT NULL,
    object_description      TEXT NOT NULL,
    data_classification     TEXT NOT NULL DEFAULT 'internal'
        CHECK (data_classification IN ('public','internal','confidential','restricted','regulated','phi','pii')),
    owner                   TEXT NOT NULL,
    steward                 TEXT,
    active                  BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(object_type, object_schema, object_name)
);

CREATE TABLE IF NOT EXISTS governance_kernel.metadata_definitions (
    metadata_definition_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metadata_object_id      UUID NOT NULL REFERENCES governance_kernel.metadata_objects(metadata_object_id),
    definition_text         TEXT NOT NULL,
    business_definition     TEXT,
    technical_definition    TEXT,
    allowed_values          JSONB,
    validation_rule         TEXT,
    effective_from          TIMESTAMPTZ NOT NULL DEFAULT now(),
    effective_to            TIMESTAMPTZ,
    approved_by             TEXT,
    approved_at             TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS governance_kernel.metadata_lineage (
    metadata_lineage_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_metadata_object_id UUID NOT NULL REFERENCES governance_kernel.metadata_objects(metadata_object_id),
    target_metadata_object_id UUID NOT NULL REFERENCES governance_kernel.metadata_objects(metadata_object_id),
    lineage_type            TEXT NOT NULL CHECK (lineage_type IN ('derived_from','copies_to','transforms_to','aggregates_to','references','validates')),
    lineage_description     TEXT NOT NULL,
    transformation_logic    TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(source_metadata_object_id, target_metadata_object_id, lineage_type)
);

CREATE TABLE IF NOT EXISTS governance_kernel.controlled_vocabulary_terms (
    vocabulary_term_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vocabulary_name         TEXT NOT NULL,
    term_code               TEXT NOT NULL,
    term_label              TEXT NOT NULL,
    term_definition         TEXT NOT NULL,
    parent_term_id          UUID REFERENCES governance_kernel.controlled_vocabulary_terms(vocabulary_term_id),
    active                  BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(vocabulary_name, term_code)
);

CREATE OR REPLACE VIEW governance_kernel.v_metadata_catalog AS
SELECT
    md.domain_code,
    md.domain_name,
    mo.object_type,
    mo.object_schema,
    mo.object_name,
    mo.object_description,
    mo.data_classification,
    mo.owner,
    mo.steward,
    mdn.business_definition,
    mdn.technical_definition
FROM governance_kernel.metadata_objects mo
LEFT JOIN governance_kernel.metadata_domains md ON md.metadata_domain_id = mo.metadata_domain_id
LEFT JOIN LATERAL (
    SELECT *
    FROM governance_kernel.metadata_definitions x
    WHERE x.metadata_object_id = mo.metadata_object_id
      AND x.effective_to IS NULL
    ORDER BY x.effective_from DESC
    LIMIT 1
) mdn ON true;

CREATE INDEX IF NOT EXISTS idx_metadata_objects_domain
ON governance_kernel.metadata_objects(metadata_domain_id);

CREATE INDEX IF NOT EXISTS idx_metadata_objects_type
ON governance_kernel.metadata_objects(object_type);

CREATE INDEX IF NOT EXISTS idx_metadata_lineage_source
ON governance_kernel.metadata_lineage(source_metadata_object_id);

CREATE INDEX IF NOT EXISTS idx_metadata_lineage_target
ON governance_kernel.metadata_lineage(target_metadata_object_id);

COMMIT;
