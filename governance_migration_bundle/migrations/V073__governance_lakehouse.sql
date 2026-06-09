-- ============================================================================
-- BioDiscoveryAI Governance Lakehouse
-- Migration: V079__governance_lakehouse.sql
-- Purpose:
--   Register governance lakehouse datasets, historical exports, analytical
--   marts, retention zones, data quality checks, and downstream BI/analytics
--   lineage for long-term governance intelligence.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_lakehouse;

CREATE TABLE IF NOT EXISTS governance_lakehouse.lakehouse_zones (
    lakehouse_zone_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_code TEXT NOT NULL UNIQUE,
    zone_name TEXT NOT NULL,
    zone_description TEXT NOT NULL,
    storage_uri TEXT NOT NULL,
    retention_policy TEXT NOT NULL,
    owner TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS governance_lakehouse.governance_exports (
    governance_export_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    export_name TEXT NOT NULL,
    export_description TEXT NOT NULL,
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    lakehouse_zone_id UUID NOT NULL REFERENCES governance_lakehouse.lakehouse_zones(lakehouse_zone_id),
    export_format TEXT NOT NULL CHECK (export_format IN ('parquet','delta','iceberg','csv','json','avro')),
    export_uri TEXT NOT NULL,
    export_sha256 TEXT,
    exported_by TEXT NOT NULL,
    exported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_count BIGINT,
    export_status TEXT NOT NULL DEFAULT 'completed'
        CHECK (export_status IN ('started','completed','failed','cancelled'))
);

CREATE TABLE IF NOT EXISTS governance_lakehouse.analytics_marts (
    analytics_mart_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mart_name TEXT NOT NULL UNIQUE,
    mart_description TEXT NOT NULL,
    mart_type TEXT NOT NULL CHECK (mart_type IN ('risk','audit','compliance','devsecops','operations','finance','executive','scientific','other')),
    storage_uri TEXT NOT NULL,
    refresh_frequency TEXT NOT NULL,
    owner TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS governance_lakehouse.lakehouse_quality_checks (
    quality_check_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_export_id UUID REFERENCES governance_lakehouse.governance_exports(governance_export_id),
    analytics_mart_id UUID REFERENCES governance_lakehouse.analytics_marts(analytics_mart_id),
    check_name TEXT NOT NULL,
    check_description TEXT NOT NULL,
    check_status TEXT NOT NULL CHECK (check_status IN ('pass','fail','warning','not_run')),
    executed_by TEXT NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE OR REPLACE VIEW governance_lakehouse.v_lakehouse_export_status AS
SELECT
    ge.export_name,
    ge.source_schema,
    ge.source_table,
    lz.zone_code,
    ge.export_format,
    ge.export_status,
    ge.row_count,
    ge.exported_at
FROM governance_lakehouse.governance_exports ge
JOIN governance_lakehouse.lakehouse_zones lz ON lz.lakehouse_zone_id = ge.lakehouse_zone_id;

INSERT INTO governance_lakehouse.lakehouse_zones (
    zone_code, zone_name, zone_description, storage_uri, retention_policy, owner
)
VALUES
('RAW_GOV','Raw Governance Zone','Immutable raw exports of governance tables.','s3://REPLACE/governance/raw','retain_10_years','Governance Data Owner'),
('CURATED_GOV','Curated Governance Zone','Validated analytics-ready governance datasets.','s3://REPLACE/governance/curated','retain_10_years','Governance Data Owner'),
('AUDIT_GOV','Audit Governance Zone','Audit-ready immutable governance evidence exports.','s3://REPLACE/governance/audit','retain_10_years','Compliance')
ON CONFLICT (zone_code) DO NOTHING;

COMMIT;
