-- ============================================================================
-- BioDiscoveryAI Database Data Dictionary and Classification
-- Migration: V105__database_data_dictionary_and_classification.sql
-- Purpose:
--   Add database-native table/column documentation, regulated criticality,
--   PHI/GxP classification, retention class, ownership, and validation status.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS governance_admin.schema_objects (
    schema_object_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schema_name TEXT NOT NULL,
    object_name TEXT NOT NULL,
    object_type TEXT NOT NULL CHECK (object_type IN ('table','partitioned_table','view','materialized_view','function','schema')),
    object_purpose TEXT NOT NULL,
    owner_role TEXT NOT NULL,
    gxp_criticality TEXT NOT NULL DEFAULT 'medium' CHECK (gxp_criticality IN ('low','medium','high','critical')),
    phi_classification TEXT NOT NULL DEFAULT 'none' CHECK (phi_classification IN ('none','potential_phi','phi','restricted_phi')),
    retention_class TEXT NOT NULL DEFAULT 'standard',
    validation_status TEXT NOT NULL DEFAULT 'draft' CHECK (validation_status IN ('draft','under_validation','validated','retired','superseded')),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(schema_name, object_name, object_type)
);

CREATE TABLE IF NOT EXISTS governance_admin.schema_columns (
    schema_column_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schema_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    column_purpose TEXT NOT NULL,
    data_classification TEXT NOT NULL DEFAULT 'operational' CHECK (data_classification IN ('operational','audit','regulated_evidence','security_sensitive','phi','financial','metadata')),
    required BOOLEAN NOT NULL DEFAULT false,
    retention_class TEXT NOT NULL DEFAULT 'inherit',
    validation_status TEXT NOT NULL DEFAULT 'draft' CHECK (validation_status IN ('draft','under_validation','validated','retired','superseded')),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(schema_name, table_name, column_name)
);

INSERT INTO governance_admin.schema_objects (
    schema_name, object_name, object_type, object_purpose, owner_role, gxp_criticality, phi_classification, retention_class, validation_status
)
SELECT n.nspname,
       c.relname,
       CASE c.relkind WHEN 'p' THEN 'partitioned_table' WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized_view' ELSE 'table' END,
       'Auto-registered database object. Complete detailed purpose during validation.',
       'Data Governance',
       CASE WHEN n.nspname IN ('evidence','archive','signing','retention') THEN 'high' ELSE 'medium' END,
       'none',
       CASE WHEN n.nspname IN ('evidence','archive','signing','retention') THEN 'regulated_evidence' ELSE 'standard' END,
       'under_validation'
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('registry','evidence','archive','reporting','signing','retention','governance_admin')
  AND c.relkind IN ('r','p','v','m')
ON CONFLICT (schema_name, object_name, object_type) DO NOTHING;

INSERT INTO governance_admin.schema_columns (
    schema_name, table_name, column_name, column_purpose, data_classification, required, validation_status
)
SELECT table_schema,
       table_name,
       column_name,
       'Auto-registered column. Complete detailed purpose during validation.',
       CASE
           WHEN table_schema IN ('evidence','archive','signing') THEN 'regulated_evidence'
           WHEN column_name ILIKE '%hash%' OR column_name ILIKE '%signature%' THEN 'audit'
           WHEN column_name ILIKE '%actor%' OR column_name ILIKE '%identity%' THEN 'security_sensitive'
           ELSE 'operational'
       END,
       is_nullable = 'NO',
       'under_validation'
FROM information_schema.columns
WHERE table_schema IN ('registry','evidence','archive','reporting','signing','retention','governance_admin')
ON CONFLICT (schema_name, table_name, column_name) DO NOTHING;

CREATE OR REPLACE VIEW governance_admin.data_dictionary_completion AS
SELECT
    'objects' AS dictionary_area,
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE object_purpose LIKE 'Auto-registered%') AS records_needing_detail,
    CASE WHEN COUNT(*) FILTER (WHERE object_purpose LIKE 'Auto-registered%') = 0 THEN 'PASS' ELSE 'INCOMPLETE' END AS completion_status
FROM governance_admin.schema_objects
UNION ALL
SELECT
    'columns',
    COUNT(*),
    COUNT(*) FILTER (WHERE column_purpose LIKE 'Auto-registered%'),
    CASE WHEN COUNT(*) FILTER (WHERE column_purpose LIKE 'Auto-registered%') = 0 THEN 'PASS' ELSE 'INCOMPLETE' END
FROM governance_admin.schema_columns;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (105, '105', 'Database data dictionary and classification', 'V105__database_data_dictionary_and_classification.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
