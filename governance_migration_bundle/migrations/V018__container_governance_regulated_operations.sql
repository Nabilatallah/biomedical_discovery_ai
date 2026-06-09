-- ============================================================================
-- BioDiscoveryAI Container Governance Regulated Operations
-- Migration: V020__container_governance_regulated_operations.sql
-- Purpose:
--   Production operating controls for regulated container governance: incident
--   response, deviations, operational runbooks, DR exercises, monitoring/SLOs,
--   periodic access reviews, supplier/vendor reviews, training, release packets,
--   operational readiness, and management review.
--
-- Dependencies:
--   V011, V015, V016, V017, V018, V019
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Operational Runbooks and SOPs
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.operational_runbooks (
    runbook_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    runbook_name             TEXT NOT NULL UNIQUE,
    runbook_version          TEXT NOT NULL,
    runbook_type             TEXT NOT NULL CHECK (runbook_type IN ('build_failure', 'scan_failure', 'signing_failure', 'release_failure', 'incident_response', 'disaster_recovery', 'backup_restore', 'access_review', 'general_ops')),
    description              TEXT NOT NULL,
    runbook_uri              TEXT NOT NULL,
    runbook_sha256           TEXT NOT NULL,
    owner                    TEXT NOT NULL,
    approval_status          TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    effective_from           DATE NOT NULL DEFAULT CURRENT_DATE,
    review_due_date          DATE NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(runbook_name, runbook_version)
);

CREATE TABLE IF NOT EXISTS container_governance.sop_acknowledgements (
    sop_acknowledgement_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    runbook_id               UUID NOT NULL REFERENCES container_governance.operational_runbooks(runbook_id),
    user_identity            TEXT NOT NULL,
    acknowledgement_meaning  TEXT NOT NULL DEFAULT 'read_and_understood',
    acknowledged_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    acknowledgement_hash     TEXT NOT NULL,
    UNIQUE(runbook_id, user_identity)
);

-- ============================================================================
-- 2. Incidents and Deviations
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.operational_incidents (
    incident_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_number          TEXT NOT NULL UNIQUE,
    related_entity_type      TEXT,
    related_entity_id        TEXT,
    incident_type            TEXT NOT NULL CHECK (incident_type IN ('security', 'compliance', 'availability', 'data_integrity', 'release_error', 'pipeline_failure', 'registry_failure', 'evidence_loss', 'other')),
    severity                 TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    incident_summary         TEXT NOT NULL,
    incident_description     TEXT NOT NULL,
    detected_by              TEXT NOT NULL,
    detected_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    containment_action       TEXT,
    root_cause               TEXT,
    status                   TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'triaged', 'contained', 'remediated', 'closed', 'cancelled')),
    capa_id                  UUID REFERENCES container_governance.capa_records(capa_id),
    closed_by                TEXT,
    closed_at                TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.deviation_records (
    deviation_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deviation_number         TEXT NOT NULL UNIQUE,
    related_entity_type      TEXT NOT NULL,
    related_entity_id        TEXT NOT NULL,
    deviation_summary        TEXT NOT NULL,
    deviation_description    TEXT NOT NULL,
    expected_process         TEXT NOT NULL,
    actual_process           TEXT NOT NULL,
    impact_assessment        TEXT NOT NULL,
    product_quality_impact   TEXT NOT NULL DEFAULT 'not_applicable' CHECK (product_quality_impact IN ('not_applicable', 'none', 'minor', 'major', 'critical')),
    opened_by                TEXT NOT NULL,
    opened_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    status                   TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'under_investigation', 'approved', 'rejected', 'closed')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    capa_id                  UUID REFERENCES container_governance.capa_records(capa_id)
);

-- ============================================================================
-- 3. Monitoring, SLOs, and Operational Metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.operational_slos (
    slo_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slo_name                 TEXT NOT NULL UNIQUE,
    slo_description          TEXT NOT NULL,
    measured_entity_type     TEXT NOT NULL,
    metric_name              TEXT NOT NULL,
    target_operator          TEXT NOT NULL CHECK (target_operator IN ('>=', '<=', '=', '>', '<')),
    target_value             NUMERIC NOT NULL,
    measurement_window       TEXT NOT NULL DEFAULT 'monthly',
    severity_on_breach       TEXT NOT NULL DEFAULT 'medium' CHECK (severity_on_breach IN ('low', 'medium', 'high', 'critical')),
    active                   BOOLEAN NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.operational_metric_observations (
    metric_observation_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slo_id                   UUID REFERENCES container_governance.operational_slos(slo_id),
    metric_name              TEXT NOT NULL,
    related_entity_type      TEXT,
    related_entity_id        TEXT,
    metric_value             NUMERIC NOT NULL,
    metric_unit              TEXT NOT NULL,
    observed_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    observation_source       TEXT NOT NULL,
    evidence_uri             TEXT,
    evidence_sha256          TEXT
);

-- ============================================================================
-- 4. Access Reviews and Privileged Access
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.access_review_campaigns (
    access_review_campaign_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_name             TEXT NOT NULL UNIQUE,
    review_scope              TEXT NOT NULL,
    reviewer                  TEXT NOT NULL,
    started_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_date                  DATE NOT NULL,
    status                    TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'completed', 'overdue', 'cancelled')),
    completed_at              TIMESTAMPTZ,
    evidence_uri              TEXT,
    evidence_sha256           TEXT
);

CREATE TABLE IF NOT EXISTS container_governance.access_review_items (
    access_review_item_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    access_review_campaign_id UUID NOT NULL REFERENCES container_governance.access_review_campaigns(access_review_campaign_id),
    user_identity            TEXT NOT NULL,
    reviewed_role            TEXT NOT NULL,
    access_decision          TEXT NOT NULL DEFAULT 'pending' CHECK (access_decision IN ('pending', 'retain', 'remove', 'modify', 'suspend')),
    decision_reason          TEXT,
    decided_by               TEXT,
    decided_at               TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.privileged_access_sessions (
    privileged_session_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_identity            TEXT NOT NULL,
    privileged_role          TEXT NOT NULL,
    access_reason            TEXT NOT NULL,
    approved_by              TEXT NOT NULL,
    started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at                 TIMESTAMPTZ,
    session_status           TEXT NOT NULL DEFAULT 'active' CHECK (session_status IN ('active', 'ended', 'revoked', 'expired')),
    session_log_uri          TEXT,
    session_log_sha256       TEXT
);

-- ============================================================================
-- 5. Supplier/Vendor and Tool Qualification
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.vendor_tool_qualification_records (
    vendor_tool_qualification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_name              TEXT NOT NULL,
    tool_name                TEXT NOT NULL,
    tool_version             TEXT NOT NULL,
    tool_category            TEXT NOT NULL CHECK (tool_category IN ('scanner', 'signing', 'registry', 'ci_cd', 'database', 'ai_provider', 'artifact_store', 'monitoring', 'other')),
    intended_use             TEXT NOT NULL,
    qualification_summary    TEXT NOT NULL,
    validation_evidence_uri  TEXT,
    validation_evidence_sha256 TEXT,
    security_review_status   TEXT NOT NULL DEFAULT 'pending' CHECK (security_review_status IN ('pending', 'approved', 'rejected', 'expired')),
    quality_review_status    TEXT NOT NULL DEFAULT 'pending' CHECK (quality_review_status IN ('pending', 'approved', 'rejected', 'expired')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    review_due_date          DATE NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(vendor_name, tool_name, tool_version)
);

-- ============================================================================
-- 6. Training Records
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.training_requirements (
    training_requirement_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    training_name            TEXT NOT NULL UNIQUE,
    training_description     TEXT NOT NULL,
    required_for_role        TEXT NOT NULL,
    recurrence_months        INT NOT NULL DEFAULT 12 CHECK (recurrence_months > 0),
    active                   BOOLEAN NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.training_completion_records (
    training_completion_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    training_requirement_id  UUID NOT NULL REFERENCES container_governance.training_requirements(training_requirement_id),
    user_identity            TEXT NOT NULL,
    completed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at               TIMESTAMPTZ NOT NULL,
    evidence_uri             TEXT,
    evidence_sha256          TEXT,
    UNIQUE(training_requirement_id, user_identity, completed_at)
);

-- ============================================================================
-- 7. Release Packets and Operational Readiness
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.regulated_release_packets (
    regulated_release_packet_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id                 UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    release_certification_id UUID REFERENCES container_governance.release_certifications(release_certification_id),
    packet_name              TEXT NOT NULL,
    packet_version           TEXT NOT NULL,
    packet_uri               TEXT NOT NULL UNIQUE,
    packet_sha256            TEXT NOT NULL,
    includes_sbom            BOOLEAN NOT NULL DEFAULT false,
    includes_validation      BOOLEAN NOT NULL DEFAULT false,
    includes_signatures      BOOLEAN NOT NULL DEFAULT false,
    includes_provenance      BOOLEAN NOT NULL DEFAULT false,
    includes_risk_acceptance BOOLEAN NOT NULL DEFAULT false,
    includes_approval_records BOOLEAN NOT NULL DEFAULT false,
    packet_status            TEXT NOT NULL DEFAULT 'draft' CHECK (packet_status IN ('draft', 'approved', 'released', 'revoked', 'superseded')),
    prepared_by              TEXT NOT NULL,
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(image_id, packet_version)
);

CREATE TABLE IF NOT EXISTS container_governance.operational_readiness_reviews (
    readiness_review_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type      TEXT NOT NULL,
    related_entity_id        TEXT NOT NULL,
    review_name              TEXT NOT NULL,
    review_scope             TEXT NOT NULL,
    runbook_ready            BOOLEAN NOT NULL DEFAULT false,
    monitoring_ready         BOOLEAN NOT NULL DEFAULT false,
    backup_ready             BOOLEAN NOT NULL DEFAULT false,
    support_ready            BOOLEAN NOT NULL DEFAULT false,
    training_ready           BOOLEAN NOT NULL DEFAULT false,
    rollback_ready           BOOLEAN NOT NULL DEFAULT false,
    review_status            TEXT NOT NULL DEFAULT 'draft' CHECK (review_status IN ('draft', 'approved', 'rejected', 'expired')),
    reviewed_by              TEXT NOT NULL,
    reviewed_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri             TEXT,
    evidence_sha256          TEXT
);

-- ============================================================================
-- 8. Management Review
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.management_review_records (
    management_review_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_period_start      DATE NOT NULL,
    review_period_end        DATE NOT NULL,
    review_title             TEXT NOT NULL,
    reviewed_metrics         JSONB NOT NULL DEFAULT '{}',
    key_risks                TEXT NOT NULL,
    key_decisions            TEXT NOT NULL,
    action_items             JSONB NOT NULL DEFAULT '[]',
    chaired_by               TEXT NOT NULL,
    attendees                TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    meeting_minutes_uri      TEXT,
    meeting_minutes_sha256   TEXT,
    review_status            TEXT NOT NULL DEFAULT 'completed' CHECK (review_status IN ('draft', 'completed', 'approved')),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (review_period_end >= review_period_start)
);

-- ============================================================================
-- 9. Enforcement: release packet readiness
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.is_regulated_release_packet_complete(p_image_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.regulated_release_packets rp
        WHERE rp.image_id = p_image_id
          AND rp.packet_status IN ('approved', 'released')
          AND rp.includes_sbom = true
          AND rp.includes_validation = true
          AND rp.includes_signatures = true
          AND rp.includes_provenance = true
          AND rp.includes_approval_records = true
    ) INTO result;
    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW container_governance.v_regulated_operations_readiness AS
SELECT
    ci.image_id,
    ci.image_name,
    ci.image_version,
    container_governance.is_image_deployable(ci.image_id) AS deployable,
    container_governance.is_release_certified(ci.image_id) AS release_certified,
    container_governance.is_regulated_release_packet_complete(ci.image_id) AS release_packet_complete,
    EXISTS (
        SELECT 1 FROM container_governance.operational_readiness_reviews rr
        WHERE rr.related_entity_type = 'container_image'
          AND rr.related_entity_id = ci.image_id::TEXT
          AND rr.review_status = 'approved'
          AND rr.runbook_ready = true
          AND rr.monitoring_ready = true
          AND rr.backup_ready = true
          AND rr.support_ready = true
          AND rr.training_ready = true
          AND rr.rollback_ready = true
    ) AS operational_readiness_approved
FROM container_governance.container_images ci;

-- ============================================================================
-- 10. Seeds and Indexes
-- ============================================================================

INSERT INTO container_governance.operational_slos (
    slo_name, slo_description, measured_entity_type, metric_name, target_operator, target_value, measurement_window, severity_on_breach
)
VALUES
('container_critical_cve_remediation_7_days', 'Critical container CVEs must be remediated or risk-accepted within 7 days.', 'vulnerability_finding', 'critical_cve_age_days', '<=', 7, 'rolling', 'critical'),
('release_evidence_completeness_100_percent', 'Every regulated release must have complete release evidence packet.', 'regulated_release_packet', 'evidence_completeness_percent', '>=', 100, 'monthly', 'high'),
('backup_restore_validation_quarterly', 'Backup/restore validation must be successfully completed at least quarterly.', 'backup_restore_validation', 'days_since_successful_restore_test', '<=', 90, 'rolling', 'high')
ON CONFLICT (slo_name) DO NOTHING;

INSERT INTO container_governance.training_requirements (
    training_name, training_description, required_for_role, recurrence_months
)
VALUES
('container_governance_sop_training', 'Required training for BioDiscoveryAI container governance SOPs.', 'all_governance_users', 12),
('gxp_electronic_records_training', 'Training on electronic records, signatures, audit trails, and data integrity expectations.', 'qa_validator,compliance_approver,release_manager', 12),
('secure_container_devsecops_training', 'Training on secure container build, scan, signing, and release practices.', 'developer,builder,security_reviewer', 12)
ON CONFLICT (training_name) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_operational_incidents_status ON container_governance.operational_incidents(status, severity, detected_at);
CREATE INDEX IF NOT EXISTS idx_deviation_records_status ON container_governance.deviation_records(status, opened_at);
CREATE INDEX IF NOT EXISTS idx_metric_observations_slo ON container_governance.operational_metric_observations(slo_id, observed_at);
CREATE INDEX IF NOT EXISTS idx_access_review_items_campaign ON container_governance.access_review_items(access_review_campaign_id);
CREATE INDEX IF NOT EXISTS idx_training_completion_user ON container_governance.training_completion_records(user_identity, expires_at);
CREATE INDEX IF NOT EXISTS idx_release_packets_image ON container_governance.regulated_release_packets(image_id);
CREATE INDEX IF NOT EXISTS idx_readiness_reviews_entity ON container_governance.operational_readiness_reviews(related_entity_type, related_entity_id);

COMMIT;
