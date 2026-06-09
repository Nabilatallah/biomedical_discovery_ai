-- ============================================================================
-- BioDiscoveryAI Container Governance Control Matrix
-- Migration: V025__container_governance_control_matrix.sql
-- Purpose:
--   Maintain a formal compliance control matrix linking container governance
--   controls, policy rules, evidence, validation, risks, CAPA, incidents,
--   release packets, and audit records to HIPAA, NIST 800-53, ISO 27001,
--   SOC 2, GxP, 21 CFR Part 11, EU AI Act, NIST AI RMF, and internal SOPs.
-- Dependencies:
--   V011 + V015 + V016 + V017 + V018 + V019 + V020 + V021 + V022 + V023 + V024
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Compliance Frameworks
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.compliance_frameworks (
    compliance_framework_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    framework_name             TEXT NOT NULL UNIQUE,
    framework_version          TEXT NOT NULL,
    framework_description      TEXT NOT NULL,

    framework_owner            TEXT NOT NULL,
    applicability_scope        TEXT NOT NULL,

    active                     BOOLEAN NOT NULL DEFAULT true,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2. Compliance Controls
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.compliance_controls (
    compliance_control_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    compliance_framework_id    UUID NOT NULL REFERENCES container_governance.compliance_frameworks(compliance_framework_id),

    control_id                 TEXT NOT NULL,
    control_title              TEXT NOT NULL,
    control_description        TEXT NOT NULL,

    control_family             TEXT,
    control_objective          TEXT NOT NULL,
    implementation_guidance    TEXT NOT NULL,

    evidence_expectation       TEXT NOT NULL,
    testing_frequency          TEXT NOT NULL,

    active                     BOOLEAN NOT NULL DEFAULT true,

    UNIQUE(compliance_framework_id, control_id)
);

-- ============================================================================
-- 3. Internal Control Implementations
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.internal_control_implementations (
    internal_control_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    control_name               TEXT NOT NULL UNIQUE,
    control_description        TEXT NOT NULL,
    control_owner              TEXT NOT NULL,

    implementation_type        TEXT NOT NULL CHECK (
        implementation_type IN (
            'sql_constraint',
            'sql_trigger',
            'sql_function',
            'policy_as_code',
            'ci_cd_gate',
            'manual_review',
            'electronic_signature',
            'runtime_control',
            'registry_control',
            'sop',
            'training',
            'monitoring'
        )
    ),

    implementation_reference   TEXT NOT NULL,
    validation_method          TEXT NOT NULL,
    evidence_source            TEXT NOT NULL,

    active                     BOOLEAN NOT NULL DEFAULT true,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 4. Framework Control Mapping
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.control_mappings (
    control_mapping_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    compliance_control_id      UUID NOT NULL REFERENCES container_governance.compliance_controls(compliance_control_id),
    internal_control_id        UUID NOT NULL REFERENCES container_governance.internal_control_implementations(internal_control_id),

    mapping_rationale          TEXT NOT NULL,
    coverage_level             TEXT NOT NULL CHECK (coverage_level IN ('full', 'partial', 'compensating', 'not_applicable')),
    gap_description            TEXT,
    remediation_plan           TEXT,

    mapped_by                  TEXT NOT NULL,
    mapped_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(compliance_control_id, internal_control_id)
);

-- ============================================================================
-- 5. Control Evidence Links
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.control_evidence_links (
    control_evidence_link_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    internal_control_id        UUID NOT NULL REFERENCES container_governance.internal_control_implementations(internal_control_id),

    evidence_entity_type       TEXT NOT NULL,
    evidence_entity_id         TEXT NOT NULL,

    evidence_summary           TEXT NOT NULL,
    evidence_uri               TEXT,
    evidence_sha256            TEXT,

    evidence_status            TEXT NOT NULL DEFAULT 'current'
        CHECK (evidence_status IN ('current', 'expired', 'superseded', 'rejected')),

    collected_by               TEXT NOT NULL,
    collected_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 6. Control Tests
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.control_tests (
    control_test_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    internal_control_id        UUID NOT NULL REFERENCES container_governance.internal_control_implementations(internal_control_id),

    test_name                  TEXT NOT NULL,
    test_description           TEXT NOT NULL,
    test_method                TEXT NOT NULL CHECK (
        test_method IN ('automated_sql', 'automated_policy', 'manual_review', 'sampling', 'walkthrough', 'technical_validation')
    ),

    expected_result            TEXT NOT NULL,
    test_frequency             TEXT NOT NULL,

    owner                      TEXT NOT NULL,
    active                     BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS container_governance.control_test_results (
    control_test_result_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    control_test_id            UUID NOT NULL REFERENCES container_governance.control_tests(control_test_id),

    test_run_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    tested_by                  TEXT NOT NULL,

    result_status              TEXT NOT NULL CHECK (result_status IN ('pass', 'fail', 'warning', 'not_applicable')),
    actual_result              TEXT NOT NULL,

    evidence_uri               TEXT,
    evidence_sha256            TEXT,

    capa_id                    UUID REFERENCES container_governance.capa_records(capa_id)
);

-- ============================================================================
-- 7. Control Coverage View
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_compliance_control_coverage AS
SELECT
    cf.framework_name,
    cf.framework_version,
    cc.control_id,
    cc.control_title,
    COUNT(cm.control_mapping_id) AS mapped_internal_controls,
    COUNT(cm.control_mapping_id) FILTER (WHERE cm.coverage_level = 'full') AS full_coverage_count,
    COUNT(cm.control_mapping_id) FILTER (WHERE cm.coverage_level = 'partial') AS partial_coverage_count,
    CASE
        WHEN COUNT(cm.control_mapping_id) FILTER (WHERE cm.coverage_level = 'full') > 0 THEN 'covered'
        WHEN COUNT(cm.control_mapping_id) FILTER (WHERE cm.coverage_level IN ('partial', 'compensating')) > 0 THEN 'partially_covered'
        ELSE 'not_covered'
    END AS coverage_status
FROM container_governance.compliance_frameworks cf
JOIN container_governance.compliance_controls cc
    ON cc.compliance_framework_id = cf.compliance_framework_id
LEFT JOIN container_governance.control_mappings cm
    ON cm.compliance_control_id = cc.compliance_control_id
GROUP BY
    cf.framework_name,
    cf.framework_version,
    cc.control_id,
    cc.control_title;

-- ============================================================================
-- 8. Control Test Status View
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_control_test_status AS
SELECT
    ici.internal_control_id,
    ici.control_name,
    ici.implementation_type,
    ct.control_test_id,
    ct.test_name,
    ct.test_frequency,
    ctr.test_run_at AS last_tested_at,
    ctr.result_status AS last_result_status,
    ctr.actual_result AS last_actual_result
FROM container_governance.internal_control_implementations ici
LEFT JOIN container_governance.control_tests ct
    ON ct.internal_control_id = ici.internal_control_id
LEFT JOIN LATERAL (
    SELECT *
    FROM container_governance.control_test_results x
    WHERE x.control_test_id = ct.control_test_id
    ORDER BY x.test_run_at DESC
    LIMIT 1
) ctr ON true;

-- ============================================================================
-- 9. Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_compliance_controls_framework
ON container_governance.compliance_controls(compliance_framework_id);

CREATE INDEX IF NOT EXISTS idx_control_mappings_compliance
ON container_governance.control_mappings(compliance_control_id);

CREATE INDEX IF NOT EXISTS idx_control_mappings_internal
ON container_governance.control_mappings(internal_control_id);

CREATE INDEX IF NOT EXISTS idx_control_evidence_links_internal
ON container_governance.control_evidence_links(internal_control_id);

CREATE INDEX IF NOT EXISTS idx_control_test_results_test
ON container_governance.control_test_results(control_test_id);

-- ============================================================================
-- 10. Seed Frameworks
-- ============================================================================

INSERT INTO container_governance.compliance_frameworks (
    framework_name,
    framework_version,
    framework_description,
    framework_owner,
    applicability_scope
)
VALUES
('NIST 800-53', 'Rev. 5', 'Security and privacy controls for information systems and organizations.', 'Security Governance', 'Container platform security, access control, audit, configuration, risk, and system integrity.'),
('ISO 27001', '2022', 'Information security management system standard.', 'Security Governance', 'Information security controls for containerized platform operations.'),
('SOC 2', 'TSC 2022', 'Trust Services Criteria for security, availability, processing integrity, confidentiality, and privacy.', 'Compliance', 'Security, availability, processing integrity, and confidentiality controls.'),
('21 CFR Part 11', 'Current', 'Electronic records and electronic signatures requirements.', 'Quality and Compliance', 'Electronic records, signatures, audit trails, validation, and system controls.'),
('GxP CSV', 'Internal', 'Computerized system validation expectations for regulated systems.', 'Quality and Validation', 'URS, FRS, DS, IQ, OQ, PQ, traceability, deviations, and CAPA.'),
('HIPAA', 'Current', 'Health information privacy and security requirements.', 'Privacy and Security', 'Protected health information security controls when applicable.'),
('NIST AI RMF', '1.0', 'AI risk management framework.', 'AI Governance', 'AI-assisted development and AI-enabled container generation governance.'),
('EU AI Act', 'Current', 'European Union AI regulatory framework.', 'AI Governance', 'Risk management, transparency, oversight, documentation, and post-market monitoring where applicable.')
ON CONFLICT (framework_name) DO NOTHING;

-- ============================================================================
-- 11. Seed Core Internal Controls
-- ============================================================================

INSERT INTO container_governance.internal_control_implementations (
    control_name,
    control_description,
    control_owner,
    implementation_type,
    implementation_reference,
    validation_method,
    evidence_source
)
VALUES
(
    'Immutable Approved Container Records',
    'Approved container image, base image, package, artifact, and audit records cannot be modified silently.',
    'Platform Engineering',
    'sql_trigger',
    'prevent_mutation_after_approval; prevent_immutable_artifact_mutation; prevent_audit_event_mutation',
    'Automated trigger test and audit review',
    'audit_events, artifacts, container_images'
),
(
    'Container Deployment Gate',
    'Containers cannot execute unless deployability, release certification, policy-as-code, incident, and revalidation gates pass.',
    'Platform Engineering',
    'sql_function',
    'is_image_deployable; is_release_certified; policy/revalidation/incident triggers',
    'Automated execution-block test',
    'execution_runs, release_certifications, policy_rule_results'
),
(
    'Electronic Signature Control',
    'Regulated approvals require electronic signature meaning, signer identity, timestamp, and hash.',
    'Quality and Compliance',
    'electronic_signature',
    'electronic_signatures',
    'Record inspection and signature-chain verification',
    'electronic_signatures'
),
(
    'Evidence Packet Control',
    'Each regulated release requires a complete evidence packet with required artifacts and reviews.',
    'Quality and Release Management',
    'manual_review',
    'release_evidence_packets; release_evidence_packet_items; release_evidence_packet_reviews',
    'Evidence packet completeness test',
    'release_evidence_packets'
)
ON CONFLICT (control_name) DO NOTHING;

COMMIT;
