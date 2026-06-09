-- ============================================================================
-- BioDiscoveryAI Release Evidence Packets
-- Migration: V022__container_governance_release_evidence_packets.sql
-- Purpose:
--   Create audit-ready release evidence packet records per image/module/release,
--   collecting SBOMs, vulnerability reports, licenses, signatures, provenance,
--   policy results, validation records, approvals, change controls, CAPA, waivers,
--   registry publication, and runtime readiness evidence.
-- Dependencies:
--   V011 + V015 + V016 + V017 + V018 + V019 + V020 + V021
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Evidence Packet Templates
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.evidence_packet_templates (
    evidence_packet_template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    template_name              TEXT NOT NULL UNIQUE,
    template_version           TEXT NOT NULL,
    template_description       TEXT NOT NULL,

    required_sections          JSONB NOT NULL,
    compliance_scope           TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],

    approval_status            TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),

    approved_by                TEXT,
    approved_at                TIMESTAMPTZ,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Release Evidence Packets
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.release_evidence_packets (
    evidence_packet_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    image_id                   UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    release_certification_id   UUID REFERENCES container_governance.release_certifications(release_certification_id),
    evidence_packet_template_id UUID REFERENCES container_governance.evidence_packet_templates(evidence_packet_template_id),

    packet_name                TEXT NOT NULL,
    packet_version             TEXT NOT NULL,
    packet_status              TEXT NOT NULL DEFAULT 'draft'
        CHECK (packet_status IN ('draft', 'assembling', 'ready_for_review', 'approved', 'rejected', 'archived', 'superseded')),

    packet_summary             TEXT NOT NULL,
    packet_uri                 TEXT,
    packet_sha256              TEXT,

    immutable                  BOOLEAN NOT NULL DEFAULT true,
    retention_policy           TEXT NOT NULL DEFAULT 'retain_10_years',
    retention_until            TIMESTAMPTZ,

    generated_by               TEXT NOT NULL,
    generated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_by                TEXT,
    approved_at                TIMESTAMPTZ,

    UNIQUE(image_id, packet_version)
);

-- ============================================================================
-- 3. Evidence Packet Items
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.release_evidence_packet_items (
    evidence_packet_item_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    evidence_packet_id         UUID NOT NULL REFERENCES container_governance.release_evidence_packets(evidence_packet_id),

    section_name               TEXT NOT NULL,
    item_type                  TEXT NOT NULL CHECK (
        item_type IN (
            'sbom',
            'vulnerability_report',
            'license_report',
            'secret_scan_report',
            'signature',
            'provenance',
            'attestation',
            'policy_result',
            'validation_record',
            'approval_record',
            'change_control',
            'capa',
            'waiver',
            'registry_publication',
            'runtime_policy',
            'execution_environment',
            'release_certification',
            'backup_restore_validation',
            'audit_export'
        )
    ),

    source_entity_type         TEXT NOT NULL,
    source_entity_id           TEXT NOT NULL,

    artifact_uri               TEXT,
    artifact_sha256            TEXT,

    required                   BOOLEAN NOT NULL DEFAULT true,
    item_status                TEXT NOT NULL DEFAULT 'pending'
        CHECK (item_status IN ('pending', 'present', 'missing', 'accepted_risk', 'not_applicable')),

    item_summary               TEXT,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(evidence_packet_id, section_name, item_type, source_entity_type, source_entity_id)
);

-- ============================================================================
-- 4. Evidence Packet Reviews
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.release_evidence_packet_reviews (
    evidence_packet_review_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    evidence_packet_id         UUID NOT NULL REFERENCES container_governance.release_evidence_packets(evidence_packet_id),

    reviewer_identity          TEXT NOT NULL,
    reviewer_role              TEXT NOT NULL CHECK (
        reviewer_role IN ('security_reviewer', 'qa_validator', 'compliance_approver', 'release_manager', 'auditor')
    ),

    review_decision            TEXT NOT NULL CHECK (review_decision IN ('approved', 'rejected', 'deferred')),
    review_comments            TEXT NOT NULL,

    reviewed_at                TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(evidence_packet_id, reviewer_identity, reviewer_role)
);

-- ============================================================================
-- 5. Packet Completeness Function
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.is_evidence_packet_complete(p_packet_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT NOT EXISTS (
        SELECT 1
        FROM container_governance.release_evidence_packet_items epi
        WHERE epi.evidence_packet_id = p_packet_id
          AND epi.required = true
          AND epi.item_status NOT IN ('present', 'accepted_risk', 'not_applicable')
    )
    INTO result;

    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION container_governance.prevent_approval_of_incomplete_evidence_packet()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.packet_status = 'approved'
       AND NOT container_governance.is_evidence_packet_complete(NEW.evidence_packet_id) THEN
        RAISE EXCEPTION
            'Evidence packet % cannot be approved because required items are missing.',
            NEW.evidence_packet_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_incomplete_packet_approval
ON container_governance.release_evidence_packets;

CREATE TRIGGER trg_prevent_incomplete_packet_approval
BEFORE UPDATE ON container_governance.release_evidence_packets
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_approval_of_incomplete_evidence_packet();

-- ============================================================================
-- 6. Packet Immutability
-- ============================================================================

CREATE OR REPLACE FUNCTION container_governance.prevent_approved_packet_mutation()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.packet_status = 'approved' AND OLD.immutable = true THEN
        RAISE EXCEPTION 'Approved evidence packet % is immutable.', OLD.evidence_packet_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_approved_packet_mutation
ON container_governance.release_evidence_packets;

CREATE TRIGGER trg_prevent_approved_packet_mutation
BEFORE UPDATE OR DELETE ON container_governance.release_evidence_packets
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_approved_packet_mutation();

-- ============================================================================
-- 7. Views
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_release_evidence_packet_status AS
SELECT
    rep.evidence_packet_id,
    rep.image_id,
    ci.image_name,
    ci.image_version,
    rep.packet_name,
    rep.packet_version,
    rep.packet_status,
    COUNT(epi.evidence_packet_item_id) AS total_items,
    COUNT(epi.evidence_packet_item_id) FILTER (WHERE epi.required = true) AS required_items,
    COUNT(epi.evidence_packet_item_id) FILTER (
        WHERE epi.required = true
          AND epi.item_status IN ('present', 'accepted_risk', 'not_applicable')
    ) AS satisfied_required_items,
    container_governance.is_evidence_packet_complete(rep.evidence_packet_id) AS is_complete
FROM container_governance.release_evidence_packets rep
JOIN container_governance.container_images ci
    ON ci.image_id = rep.image_id
LEFT JOIN container_governance.release_evidence_packet_items epi
    ON epi.evidence_packet_id = rep.evidence_packet_id
GROUP BY
    rep.evidence_packet_id,
    rep.image_id,
    ci.image_name,
    ci.image_version,
    rep.packet_name,
    rep.packet_version,
    rep.packet_status;

-- ============================================================================
-- 8. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_release_evidence_packets_image
ON container_governance.release_evidence_packets(image_id);

CREATE INDEX IF NOT EXISTS idx_release_evidence_packet_items_packet
ON container_governance.release_evidence_packet_items(evidence_packet_id);

CREATE INDEX IF NOT EXISTS idx_release_evidence_packet_reviews_packet
ON container_governance.release_evidence_packet_reviews(evidence_packet_id);

-- ============================================================================
-- 9. Seed Template
-- ============================================================================

INSERT INTO container_governance.evidence_packet_templates (
    template_name,
    template_version,
    template_description,
    required_sections,
    compliance_scope,
    approval_status,
    approved_by,
    approved_at
)
VALUES (
    'regulated_container_release_packet',
    '1.0.0',
    'Audit-ready evidence packet template for regulated container release.',
    '[
        "container_identity",
        "source_code_lineage",
        "dockerfile_and_apptainer_lineage",
        "sbom",
        "vulnerability_review",
        "license_review",
        "secret_scan",
        "signatures",
        "provenance",
        "policy_as_code",
        "validation_iq_oq_pq",
        "approval_workflow",
        "change_control",
        "capa_and_waivers",
        "registry_publication",
        "runtime_policy",
        "backup_restore_evidence",
        "release_certification"
    ]'::jsonb,
    ARRAY['GxP', '21CFR11', 'NIST-800-53', 'ISO-27001', 'SOC2', 'HIPAA'],
    'approved',
    'Architecture Review Board',
    now()
)
ON CONFLICT (template_name) DO NOTHING;

COMMIT;
