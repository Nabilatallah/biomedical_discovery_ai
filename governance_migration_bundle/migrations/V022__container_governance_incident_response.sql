-- ============================================================================
-- BioDiscoveryAI Container Governance Incident Response
-- Migration: V024__container_governance_incident_response.sql
-- Purpose:
--   Create audit-ready incident response records for container security,
--   supply-chain, registry, runtime, policy, validation, data-integrity,
--   backup/restore, and compliance incidents, with containment, eradication,
--   recovery, CAPA, postmortem, notification, and regulatory evidence.
-- Dependencies:
--   V011 + V015 + V016 + V017 + V018 + V019 + V020 + V021 + V022 + V023
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Incident Records
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.security_incidents (
    incident_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    incident_number            TEXT NOT NULL UNIQUE,
    incident_title             TEXT NOT NULL,
    incident_description       TEXT NOT NULL,

    incident_type              TEXT NOT NULL CHECK (
        incident_type IN (
            'container_vulnerability',
            'malicious_package',
            'registry_compromise',
            'signature_failure',
            'provenance_failure',
            'secret_exposure',
            'runtime_escape_attempt',
            'policy_bypass',
            'audit_integrity_failure',
            'backup_restore_failure',
            'validation_failure',
            'compliance_deviation',
            'other'
        )
    ),

    severity                   TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    priority                   TEXT NOT NULL CHECK (priority IN ('p1', 'p2', 'p3', 'p4')),

    detection_source           TEXT NOT NULL,
    detected_by                TEXT NOT NULL,
    detected_at                TIMESTAMPTZ NOT NULL DEFAULT now(),

    status                     TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'triage', 'contained', 'eradicated', 'recovered', 'postmortem', 'closed', 'cancelled')),

    owner                      TEXT NOT NULL,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at                  TIMESTAMPTZ
);

-- ============================================================================
-- 2. Incident Affected Assets
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.incident_affected_assets (
    incident_affected_asset_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    incident_id                UUID NOT NULL REFERENCES container_governance.security_incidents(incident_id),

    asset_type                 TEXT NOT NULL CHECK (
        asset_type IN (
            'container_image',
            'base_image',
            'package',
            'build',
            'registry',
            'runtime_environment',
            'artifact',
            'release_certification',
            'execution_run',
            'database_record'
        )
    ),

    asset_id                   TEXT NOT NULL,
    impact_summary             TEXT NOT NULL,
    containment_required       BOOLEAN NOT NULL DEFAULT true,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(incident_id, asset_type, asset_id)
);

-- ============================================================================
-- 3. Incident Actions
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.incident_actions (
    incident_action_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    incident_id                UUID NOT NULL REFERENCES container_governance.security_incidents(incident_id),

    action_phase               TEXT NOT NULL CHECK (
        action_phase IN ('triage', 'containment', 'eradication', 'recovery', 'communication', 'postmortem', 'capa')
    ),

    action_title               TEXT NOT NULL,
    action_description         TEXT NOT NULL,

    action_owner               TEXT NOT NULL,
    due_at                     TIMESTAMPTZ,

    status                     TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'in_progress', 'completed', 'blocked', 'cancelled')),

    evidence_uri               TEXT,
    evidence_sha256            TEXT,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at               TIMESTAMPTZ
);

-- ============================================================================
-- 4. Incident Notifications
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.incident_notifications (
    incident_notification_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    incident_id                UUID NOT NULL REFERENCES container_governance.security_incidents(incident_id),

    notification_type          TEXT NOT NULL CHECK (
        notification_type IN ('internal', 'security', 'qa', 'compliance', 'legal', 'vendor', 'customer', 'regulator')
    ),

    recipient_group            TEXT NOT NULL,
    notification_summary       TEXT NOT NULL,

    notification_required      BOOLEAN NOT NULL DEFAULT true,
    notified_by                TEXT,
    notified_at                TIMESTAMPTZ,

    evidence_uri               TEXT,
    evidence_sha256            TEXT,

    status                     TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'sent', 'not_required', 'cancelled')),

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5. Incident Postmortems
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.incident_postmortems (
    incident_postmortem_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    incident_id                UUID NOT NULL UNIQUE REFERENCES container_governance.security_incidents(incident_id),

    root_cause                 TEXT NOT NULL,
    contributing_factors       TEXT NOT NULL,
    impact_assessment          TEXT NOT NULL,
    timeline_summary           TEXT NOT NULL,

    lessons_learned            TEXT NOT NULL,
    preventive_controls        TEXT NOT NULL,
    capa_id                    UUID REFERENCES container_governance.capa_records(capa_id),

    authored_by                TEXT NOT NULL,
    reviewed_by                TEXT,
    approved_by                TEXT,

    status                     TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'under_review', 'approved', 'rejected')),

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at                TIMESTAMPTZ
);

-- ============================================================================
-- 6. Critical Incident Execution Freeze
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.has_active_blocking_incident(p_image_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.security_incidents si
        JOIN container_governance.incident_affected_assets iaa
            ON iaa.incident_id = si.incident_id
        WHERE iaa.asset_type = 'container_image'
          AND iaa.asset_id = p_image_id::TEXT
          AND si.severity IN ('high', 'critical')
          AND si.status NOT IN ('recovered', 'postmortem', 'closed', 'cancelled')
    )
    INTO result;

    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION container_governance.prevent_execution_during_blocking_incident()
RETURNS TRIGGER AS $$
BEGIN
    IF container_governance.has_active_blocking_incident(NEW.image_id) THEN
        RAISE EXCEPTION
            'Image % is blocked due to an active high/critical incident.',
            NEW.image_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_execution_during_incident
ON container_governance.execution_runs;

CREATE TRIGGER trg_prevent_execution_during_incident
BEFORE INSERT ON container_governance.execution_runs
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_execution_during_blocking_incident();

-- ============================================================================
-- 7. Views
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_active_container_incidents AS
SELECT
    si.incident_id,
    si.incident_number,
    si.incident_title,
    si.incident_type,
    si.severity,
    si.priority,
    si.status,
    si.owner,
    iaa.asset_type,
    iaa.asset_id,
    iaa.impact_summary,
    si.detected_at
FROM container_governance.security_incidents si
JOIN container_governance.incident_affected_assets iaa
    ON iaa.incident_id = si.incident_id
WHERE si.status NOT IN ('closed', 'cancelled');

-- ============================================================================
-- 8. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_security_incidents_status
ON container_governance.security_incidents(status, severity);

CREATE INDEX IF NOT EXISTS idx_incident_affected_assets_asset
ON container_governance.incident_affected_assets(asset_type, asset_id);

CREATE INDEX IF NOT EXISTS idx_incident_actions_incident
ON container_governance.incident_actions(incident_id);

CREATE INDEX IF NOT EXISTS idx_incident_notifications_incident
ON container_governance.incident_notifications(incident_id);

COMMIT;
