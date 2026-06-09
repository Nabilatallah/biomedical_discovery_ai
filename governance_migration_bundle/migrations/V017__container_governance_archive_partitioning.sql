-- ============================================================================
-- BioDiscoveryAI Container Governance Archive and Partitioning
-- Migration: V019__container_governance_archive_partitioning.sql
-- Purpose:
--   Enterprise partition planning, partition automation metadata, archive jobs,
--   WORM/Object Lock records, evidence snapshots, retention, legal holds,
--   archive verification, and tamper-evident export manifests.
--
-- Dependencies:
--   V011, V015
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Archive Storage Backends
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.archive_storage_backends (
    archive_backend_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    backend_name             TEXT NOT NULL UNIQUE,
    backend_type             TEXT NOT NULL CHECK (backend_type IN ('s3_object_lock', 'azure_immutable_blob', 'gcs_bucket_lock', 'filesystem_worm', 'tape_archive', 'other')),
    backend_uri              TEXT NOT NULL,
    immutability_mode        TEXT NOT NULL CHECK (immutability_mode IN ('governance', 'compliance', 'worm', 'none')),
    default_retention_years  INT NOT NULL DEFAULT 7 CHECK (default_retention_years > 0),
    encryption_required      BOOLEAN NOT NULL DEFAULT true,
    kms_key_reference        TEXT,
    owner                    TEXT NOT NULL,
    approval_status          TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Partition Plans and Concrete Partition Registry
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.partition_plans (
    partition_plan_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_table_schema      TEXT NOT NULL,
    parent_table_name        TEXT NOT NULL,
    partition_column         TEXT NOT NULL,
    partition_strategy       TEXT NOT NULL DEFAULT 'range_monthly' CHECK (partition_strategy IN ('range_monthly', 'range_quarterly', 'range_yearly')),
    precreate_months         INT NOT NULL DEFAULT 6 CHECK (precreate_months >= 0),
    retention_months         INT NOT NULL DEFAULT 84 CHECK (retention_months > 0),
    archive_after_months     INT NOT NULL DEFAULT 24 CHECK (archive_after_months >= 0),
    active                   BOOLEAN NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(parent_table_schema, parent_table_name)
);

CREATE TABLE IF NOT EXISTS container_governance.partition_registry (
    partition_registry_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partition_plan_id        UUID NOT NULL REFERENCES container_governance.partition_plans(partition_plan_id),
    partition_schema         TEXT NOT NULL,
    partition_name           TEXT NOT NULL UNIQUE,
    range_start              TIMESTAMPTZ NOT NULL,
    range_end                TIMESTAMPTZ NOT NULL,
    partition_status         TEXT NOT NULL DEFAULT 'planned' CHECK (partition_status IN ('planned', 'created', 'archived', 'dropped', 'failed')),
    row_count_estimate       BIGINT,
    size_bytes_estimate      BIGINT,
    created_by               TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    archived_at              TIMESTAMPTZ,
    CHECK (range_end > range_start)
);

-- ============================================================================
-- 3. Archive Jobs, Manifests, and Verification
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.archive_jobs (
    archive_job_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_backend_id       UUID NOT NULL REFERENCES container_governance.archive_storage_backends(archive_backend_id),
    partition_registry_id    UUID REFERENCES container_governance.partition_registry(partition_registry_id),
    archive_scope            TEXT NOT NULL,
    archive_reason           TEXT NOT NULL CHECK (archive_reason IN ('retention_policy', 'legal_hold', 'system_snapshot', 'release_evidence', 'manual_request', 'decommission')),
    requested_by             TEXT NOT NULL,
    requested_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    status                   TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'approved', 'running', 'passed', 'failed', 'cancelled')),
    started_at               TIMESTAMPTZ,
    finished_at              TIMESTAMPTZ,
    failure_reason           TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.archive_manifests (
    archive_manifest_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_job_id           UUID NOT NULL REFERENCES container_governance.archive_jobs(archive_job_id),
    manifest_uri             TEXT NOT NULL UNIQUE,
    manifest_sha256          TEXT NOT NULL,
    manifest_format          TEXT NOT NULL DEFAULT 'json',
    item_count               BIGINT NOT NULL DEFAULT 0,
    total_size_bytes         BIGINT,
    root_hash                TEXT NOT NULL,
    signed                   BOOLEAN NOT NULL DEFAULT false,
    signature_uri            TEXT,
    signature_sha256         TEXT,
    generated_by             TEXT NOT NULL,
    generated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.archive_manifest_items (
    archive_manifest_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_manifest_id      UUID NOT NULL REFERENCES container_governance.archive_manifests(archive_manifest_id),
    source_entity_type       TEXT NOT NULL,
    source_entity_id         TEXT NOT NULL,
    source_uri               TEXT NOT NULL,
    archive_uri              TEXT NOT NULL,
    source_sha256            TEXT NOT NULL,
    archive_sha256           TEXT NOT NULL,
    size_bytes               BIGINT,
    archived_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(archive_manifest_id, archive_uri)
);

CREATE TABLE IF NOT EXISTS container_governance.archive_verifications (
    archive_verification_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_manifest_id      UUID NOT NULL REFERENCES container_governance.archive_manifests(archive_manifest_id),
    verification_type        TEXT NOT NULL CHECK (verification_type IN ('hash_check', 'restore_test', 'signature_check', 'object_lock_check', 'full_integrity_check')),
    verification_status      TEXT NOT NULL CHECK (verification_status IN ('pass', 'fail', 'partial', 'blocked')),
    verified_item_count      BIGINT NOT NULL DEFAULT 0,
    failed_item_count        BIGINT NOT NULL DEFAULT 0,
    verification_summary     TEXT NOT NULL,
    evidence_uri             TEXT,
    evidence_sha256          TEXT,
    verified_by              TEXT NOT NULL,
    verified_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 4. Legal Holds and Retention Overrides
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.legal_holds (
    legal_hold_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hold_name                TEXT NOT NULL UNIQUE,
    hold_description         TEXT NOT NULL,
    related_entity_type      TEXT NOT NULL,
    related_entity_id        TEXT NOT NULL,
    hold_reason              TEXT NOT NULL,
    requested_by             TEXT NOT NULL,
    approved_by              TEXT NOT NULL,
    effective_from           DATE NOT NULL DEFAULT CURRENT_DATE,
    released_on              DATE,
    release_reason           TEXT,
    status                   TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released', 'expired')),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.retention_policy_rules (
    retention_policy_rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name                TEXT NOT NULL UNIQUE,
    entity_type              TEXT NOT NULL,
    evidence_type            TEXT,
    minimum_retention_years  INT NOT NULL CHECK (minimum_retention_years > 0),
    disposition_action       TEXT NOT NULL CHECK (disposition_action IN ('archive', 'delete_after_archive', 'retain_forever', 'legal_review')),
    compliance_basis         TEXT NOT NULL,
    active                   BOOLEAN NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5. Snapshot Signing
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.governance_snapshots (
    governance_snapshot_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_name            TEXT NOT NULL,
    snapshot_scope           TEXT NOT NULL,
    snapshot_query           TEXT NOT NULL,
    snapshot_uri             TEXT NOT NULL UNIQUE,
    snapshot_sha256          TEXT NOT NULL,
    record_count             BIGINT NOT NULL,
    root_hash                TEXT NOT NULL,
    signature_uri            TEXT,
    signature_sha256         TEXT,
    created_by               TEXT NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    retention_until          DATE NOT NULL
);

-- ============================================================================
-- 6. Views and Seeds
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_archive_readiness AS
SELECT
    pp.partition_plan_id,
    pp.parent_table_schema,
    pp.parent_table_name,
    pp.partition_column,
    pp.retention_months,
    pp.archive_after_months,
    COUNT(pr.partition_registry_id) AS partition_count,
    COUNT(pr.partition_registry_id) FILTER (WHERE pr.partition_status = 'created') AS active_partitions,
    COUNT(pr.partition_registry_id) FILTER (WHERE pr.partition_status = 'archived') AS archived_partitions
FROM container_governance.partition_plans pp
LEFT JOIN container_governance.partition_registry pr ON pp.partition_plan_id = pr.partition_plan_id
GROUP BY pp.partition_plan_id, pp.parent_table_schema, pp.parent_table_name, pp.partition_column, pp.retention_months, pp.archive_after_months;

INSERT INTO container_governance.retention_policy_rules (
    rule_name, entity_type, evidence_type, minimum_retention_years, disposition_action, compliance_basis
)
VALUES
('retain_container_evidence_7_years', 'container_evidence', NULL, 7, 'archive', 'GxP/21CFR11/SOC2 evidence retention'),
('retain_audit_events_7_years', 'audit_event', NULL, 7, 'archive', 'Immutable audit traceability'),
('retain_release_certifications_10_years', 'release_certification', NULL, 10, 'archive', 'Regulated release packet retention'),
('retain_validation_records_10_years', 'validation_record', NULL, 10, 'archive', 'CSV/IQ/OQ/PQ validation retention')
ON CONFLICT (rule_name) DO NOTHING;

INSERT INTO container_governance.partition_plans (
    parent_table_schema, parent_table_name, partition_column, partition_strategy, precreate_months, retention_months, archive_after_months
)
VALUES
('container_governance', 'audit_events', 'created_at', 'range_monthly', 6, 84, 24),
('container_governance', 'execution_runs', 'created_at', 'range_monthly', 6, 84, 24),
('container_governance', 'container_evidence', 'generated_at', 'range_monthly', 6, 84, 24),
('container_governance', 'vulnerability_findings', 'detected_at', 'range_monthly', 6, 84, 24),
('container_governance', 'artifacts', 'generated_at', 'range_monthly', 6, 84, 24)
ON CONFLICT (parent_table_schema, parent_table_name) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_partition_registry_plan ON container_governance.partition_registry(partition_plan_id, range_start, range_end);
CREATE INDEX IF NOT EXISTS idx_archive_jobs_status ON container_governance.archive_jobs(status, requested_at);
CREATE INDEX IF NOT EXISTS idx_archive_manifest_items_manifest ON container_governance.archive_manifest_items(archive_manifest_id);
CREATE INDEX IF NOT EXISTS idx_archive_verifications_manifest ON container_governance.archive_verifications(archive_manifest_id);
CREATE INDEX IF NOT EXISTS idx_legal_holds_entity ON container_governance.legal_holds(related_entity_type, related_entity_id, status);
CREATE INDEX IF NOT EXISTS idx_governance_snapshots_created ON container_governance.governance_snapshots(created_at);

COMMIT;
