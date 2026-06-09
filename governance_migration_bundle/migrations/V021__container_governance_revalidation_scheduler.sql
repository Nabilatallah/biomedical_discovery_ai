-- ============================================================================
-- BioDiscoveryAI Revalidation Scheduler
-- Migration: V023__container_governance_revalidation_scheduler.sql
-- Purpose:
--   Schedule, track, and enforce periodic revalidation for container images,
--   packages, base images, SBOMs, vulnerabilities, licenses, signatures,
--   provenance, runtime policies, execution environments, backup/restore tests,
--   and release evidence packets.
-- Dependencies:
--   V011 + V015 + V016 + V017 + V018 + V019 + V020 + V021 + V022
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Revalidation Policies
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.revalidation_policies (
    revalidation_policy_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    policy_name                TEXT NOT NULL UNIQUE,
    policy_description         TEXT NOT NULL,

    entity_type                TEXT NOT NULL CHECK (
        entity_type IN (
            'container_image',
            'base_image',
            'approved_package',
            'runtime_policy',
            'execution_environment',
            'release_certification',
            'evidence_packet',
            'registry_publication',
            'backup_restore'
        )
    ),

    frequency_days             INT NOT NULL CHECK (frequency_days > 0),
    grace_period_days          INT NOT NULL DEFAULT 0 CHECK (grace_period_days >= 0),

    required_checks            JSONB NOT NULL,
    blocking_after_due         BOOLEAN NOT NULL DEFAULT true,

    approval_status            TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),

    approved_by                TEXT,
    approved_at                TIMESTAMPTZ,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Revalidation Schedule
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.revalidation_schedule (
    revalidation_schedule_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    revalidation_policy_id     UUID NOT NULL REFERENCES container_governance.revalidation_policies(revalidation_policy_id),

    related_entity_type        TEXT NOT NULL,
    related_entity_id          TEXT NOT NULL,

    last_revalidated_at        TIMESTAMPTZ,
    next_due_at                TIMESTAMPTZ NOT NULL,

    status                     TEXT NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'due', 'overdue', 'completed', 'waived', 'retired')),

    owner                      TEXT NOT NULL,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(revalidation_policy_id, related_entity_type, related_entity_id)
);

-- ============================================================================
-- 3. Revalidation Runs
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.revalidation_runs (
    revalidation_run_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    revalidation_schedule_id   UUID NOT NULL REFERENCES container_governance.revalidation_schedule(revalidation_schedule_id),

    run_type                   TEXT NOT NULL CHECK (
        run_type IN (
            'cve_rescan',
            'license_rescan',
            'secret_rescan',
            'signature_verification',
            'provenance_verification',
            'sbom_regeneration',
            'policy_reevaluation',
            'runtime_policy_review',
            'backup_restore_test',
            'validation_review',
            'release_packet_review'
        )
    ),

    run_status                 TEXT NOT NULL DEFAULT 'started'
        CHECK (run_status IN ('started', 'passed', 'failed', 'warning', 'cancelled', 'accepted_risk')),

    started_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at                TIMESTAMPTZ,

    executed_by                TEXT NOT NULL,
    summary                    TEXT NOT NULL,
    evidence_uri               TEXT,
    evidence_sha256            TEXT
);

-- ============================================================================
-- 4. Overdue Revalidation Enforcement
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.has_overdue_blocking_revalidation(p_entity_type TEXT, p_entity_id TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.revalidation_schedule rs
        JOIN container_governance.revalidation_policies rp
            ON rp.revalidation_policy_id = rs.revalidation_policy_id
        WHERE rs.related_entity_type = p_entity_type
          AND rs.related_entity_id = p_entity_id
          AND rp.blocking_after_due = true
          AND rs.status IN ('due', 'overdue')
          AND now() > (rs.next_due_at + (rp.grace_period_days || ' days')::interval)
    )
    INTO result;

    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION container_governance.prevent_execution_with_overdue_revalidation()
RETURNS TRIGGER AS $$
BEGIN
    IF container_governance.has_overdue_blocking_revalidation('container_image', NEW.image_id::TEXT) THEN
        RAISE EXCEPTION
            'Image % has overdue blocking revalidation and cannot execute.',
            NEW.image_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_overdue_revalidation_execution
ON container_governance.execution_runs;

CREATE TRIGGER trg_prevent_overdue_revalidation_execution
BEFORE INSERT ON container_governance.execution_runs
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_execution_with_overdue_revalidation();

-- ============================================================================
-- 5. Revalidation Schedule Refresh Function
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.mark_revalidation_due()
RETURNS INT AS $$
DECLARE
    updated_count INT;
BEGIN
    UPDATE container_governance.revalidation_schedule
    SET status = CASE
        WHEN next_due_at < now() THEN 'overdue'
        WHEN next_due_at <= now() + interval '7 days' THEN 'due'
        ELSE status
    END
    WHERE status = 'scheduled'
      AND next_due_at <= now() + interval '7 days';

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. Views
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_revalidation_status AS
SELECT
    rs.revalidation_schedule_id,
    rp.policy_name,
    rp.entity_type,
    rs.related_entity_type,
    rs.related_entity_id,
    rs.last_revalidated_at,
    rs.next_due_at,
    rs.status,
    rp.blocking_after_due,
    CASE
        WHEN now() > (rs.next_due_at + (rp.grace_period_days || ' days')::interval)
             AND rp.blocking_after_due = true
        THEN true
        ELSE false
    END AS blocking_overdue,
    rs.owner
FROM container_governance.revalidation_schedule rs
JOIN container_governance.revalidation_policies rp
    ON rp.revalidation_policy_id = rs.revalidation_policy_id;

-- ============================================================================
-- 7. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_revalidation_schedule_entity
ON container_governance.revalidation_schedule(related_entity_type, related_entity_id);

CREATE INDEX IF NOT EXISTS idx_revalidation_schedule_due
ON container_governance.revalidation_schedule(next_due_at, status);

CREATE INDEX IF NOT EXISTS idx_revalidation_runs_schedule
ON container_governance.revalidation_runs(revalidation_schedule_id);

-- ============================================================================
-- 8. Seed Standard Revalidation Policies
-- ============================================================================

INSERT INTO container_governance.revalidation_policies (
    policy_name,
    policy_description,
    entity_type,
    frequency_days,
    grace_period_days,
    required_checks,
    blocking_after_due,
    approval_status,
    approved_by,
    approved_at
)
VALUES
(
    'container_image_30_day_security_revalidation',
    'Every regulated container image must undergo CVE, license, secret, signature, provenance, and policy revalidation every 30 days.',
    'container_image',
    30,
    7,
    '["cve_rescan","license_rescan","secret_rescan","signature_verification","provenance_verification","policy_reevaluation"]'::jsonb,
    true,
    'approved',
    'Architecture Review Board',
    now()
),
(
    'backup_restore_quarterly_validation',
    'Backup and restore capability must be validated at least quarterly.',
    'backup_restore',
    90,
    14,
    '["backup_restore_test"]'::jsonb,
    true,
    'approved',
    'Architecture Review Board',
    now()
)
ON CONFLICT (policy_name) DO NOTHING;

COMMIT;
