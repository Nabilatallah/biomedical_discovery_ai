-- ============================================================================
-- BioDiscoveryAI Backup, Restore, and Disaster Recovery Evidence
-- Migration: V107__backup_restore_and_disaster_recovery_evidence.sql
-- Purpose:
--   Add SQL-side evidence tables for backup jobs, restore tests, checksum
--   verification, RPO/RTO proof, and DR attestations.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS governance_admin.backup_jobs (
    backup_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    backup_job_code TEXT NOT NULL UNIQUE,
    backup_type TEXT NOT NULL CHECK (backup_type IN ('full','incremental','wal_archive','snapshot','logical_dump')),
    backup_status TEXT NOT NULL CHECK (backup_status IN ('started','completed','failed','cancelled')),
    storage_uri TEXT NOT NULL,
    backup_sha256 TEXT,
    size_bytes BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    initiated_by TEXT REFERENCES registry.actors(actor_id),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_backup_jobs_time_quality CHECK (completed_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS governance_admin.restore_tests (
    restore_test_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    backup_job_id UUID REFERENCES governance_admin.backup_jobs(backup_job_id),
    restore_test_code TEXT NOT NULL UNIQUE,
    restore_environment TEXT NOT NULL,
    restore_status TEXT NOT NULL CHECK (restore_status IN ('planned','started','pass','fail','cancelled')),
    rpo_seconds INT CHECK (rpo_seconds IS NULL OR rpo_seconds >= 0),
    rto_seconds INT CHECK (rto_seconds IS NULL OR rto_seconds >= 0),
    row_count_verified BOOLEAN NOT NULL DEFAULT false,
    checksum_verified BOOLEAN NOT NULL DEFAULT false,
    audit_chain_verified BOOLEAN NOT NULL DEFAULT false,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    tested_by TEXT REFERENCES registry.actors(actor_id),
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_restore_tests_time_quality CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT chk_restore_tests_pass_evidence CHECK (restore_status <> 'pass' OR (row_count_verified AND checksum_verified AND audit_chain_verified))
);

CREATE TABLE IF NOT EXISTS governance_admin.disaster_recovery_attestations (
    dr_attestation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attestation_code TEXT NOT NULL UNIQUE,
    restore_test_id UUID REFERENCES governance_admin.restore_tests(restore_test_id),
    attestation_status TEXT NOT NULL CHECK (attestation_status IN ('draft','approved','rejected','superseded')),
    rpo_target_seconds INT NOT NULL CHECK (rpo_target_seconds >= 0),
    rto_target_seconds INT NOT NULL CHECK (rto_target_seconds >= 0),
    rpo_met BOOLEAN NOT NULL DEFAULT false,
    rto_met BOOLEAN NOT NULL DEFAULT false,
    attested_by TEXT REFERENCES registry.actors(actor_id),
    attested_at TIMESTAMPTZ,
    approval_id UUID REFERENCES evidence.approvals(approval_id),
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_dr_attestation_approval_fields CHECK (attestation_status <> 'approved' OR (attested_by IS NOT NULL AND attested_at IS NOT NULL AND approval_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_backup_jobs_status ON governance_admin.backup_jobs(backup_status, started_at);
CREATE INDEX IF NOT EXISTS idx_restore_tests_status ON governance_admin.restore_tests(restore_status, completed_at);
CREATE INDEX IF NOT EXISTS idx_dr_attestations_status ON governance_admin.disaster_recovery_attestations(attestation_status, created_at);

CREATE OR REPLACE VIEW governance_admin.backup_restore_readiness AS
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM governance_admin.restore_tests
            WHERE restore_status = 'pass'
              AND row_count_verified
              AND checksum_verified
              AND audit_chain_verified
              AND completed_at >= now() - INTERVAL '90 days'
        ) THEN 'PASS'
        ELSE 'FAIL'
    END AS readiness_status,
    (SELECT MAX(completed_at) FROM governance_admin.restore_tests WHERE restore_status = 'pass') AS last_successful_restore_test_at,
    (SELECT COUNT(*) FROM governance_admin.backup_jobs WHERE backup_status = 'completed' AND completed_at >= now() - INTERVAL '7 days') AS completed_backups_last_7_days;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (107, '107', 'Backup restore and disaster recovery evidence', 'V107__backup_restore_and_disaster_recovery_evidence.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
