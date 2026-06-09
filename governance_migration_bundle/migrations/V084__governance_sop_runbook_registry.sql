-- ============================================================================
-- BioDiscoveryAI Governance SOP and Runbook Registry
-- Migration: V090__governance_sop_runbook_registry.sql
-- Purpose:
--   Register SOPs, runbooks, work instructions, operational procedures,
--   emergency procedures, periodic review, training linkage, and evidence.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_contracts;

CREATE TABLE IF NOT EXISTS governance_contracts.sop_runbook_catalog (
    sop_runbook_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_code TEXT NOT NULL UNIQUE,
    document_title TEXT NOT NULL,
    document_type TEXT NOT NULL CHECK (
        document_type IN ('sop','runbook','work_instruction','policy','standard','emergency_procedure','checklist','template')
    ),
    document_description TEXT NOT NULL,
    owning_domain TEXT NOT NULL,
    owner TEXT NOT NULL,
    current_version TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','under_review','approved','rejected','retired','superseded')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    effective_date DATE,
    review_due_date DATE,
    artifact_uri TEXT,
    artifact_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.sop_runbook_steps (
    sop_runbook_step_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sop_runbook_id UUID NOT NULL REFERENCES governance_contracts.sop_runbook_catalog(sop_runbook_id),
    step_number INT NOT NULL,
    step_title TEXT NOT NULL,
    step_description TEXT NOT NULL,
    responsible_role TEXT NOT NULL,
    expected_evidence TEXT,
    risk_if_skipped TEXT,
    UNIQUE(sop_runbook_id, step_number)
);

CREATE TABLE IF NOT EXISTS governance_contracts.sop_runbook_reviews (
    sop_runbook_review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sop_runbook_id UUID NOT NULL REFERENCES governance_contracts.sop_runbook_catalog(sop_runbook_id),
    review_type TEXT NOT NULL CHECK (review_type IN ('periodic','change_driven','incident_driven','audit_driven')),
    review_decision TEXT NOT NULL CHECK (review_decision IN ('approved','needs_revision','retire','supersede')),
    review_comments TEXT NOT NULL,
    reviewed_by TEXT NOT NULL,
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_contracts.sop_training_requirements (
    sop_training_requirement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sop_runbook_id UUID NOT NULL REFERENCES governance_contracts.sop_runbook_catalog(sop_runbook_id),
    required_role TEXT NOT NULL,
    training_frequency TEXT NOT NULL DEFAULT 'annual',
    competency_required BOOLEAN NOT NULL DEFAULT true,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(sop_runbook_id, required_role)
);

CREATE TABLE IF NOT EXISTS governance_contracts.sop_execution_records (
    sop_execution_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sop_runbook_id UUID NOT NULL REFERENCES governance_contracts.sop_runbook_catalog(sop_runbook_id),
    executed_by TEXT NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    execution_context TEXT NOT NULL,
    execution_status TEXT NOT NULL CHECK (execution_status IN ('completed','failed','partial','not_applicable')),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE OR REPLACE VIEW governance_contracts.v_sop_readiness AS
SELECT
    s.document_code,
    s.document_title,
    s.document_type,
    s.current_version,
    s.approval_status,
    s.review_due_date,
    COUNT(st.sop_runbook_step_id) AS step_count,
    COUNT(tr.sop_training_requirement_id) AS training_requirement_count
FROM governance_contracts.sop_runbook_catalog s
LEFT JOIN governance_contracts.sop_runbook_steps st ON st.sop_runbook_id = s.sop_runbook_id
LEFT JOIN governance_contracts.sop_training_requirements tr ON tr.sop_runbook_id = s.sop_runbook_id
GROUP BY s.document_code, s.document_title, s.document_type, s.current_version, s.approval_status, s.review_due_date;

INSERT INTO governance_contracts.sop_runbook_catalog (
    document_code, document_title, document_type, document_description, owning_domain, owner, current_version, approval_status, approved_by, approved_at
)
VALUES
('SOP-CONTAINER-RELEASE','Container Release SOP','sop','Procedure for approving, validating, signing, certifying, and releasing governed containers.','container_governance','Compliance Engineering','1.0.0','approved','Architecture Review Board',now()),
('RB-INCIDENT-RESPONSE','Container Governance Incident Response Runbook','runbook','Operational runbook for responding to container, supply-chain, policy, and compliance incidents.','security_operations','Security Engineering','1.0.0','approved','Architecture Review Board',now()),
('SOP-EVIDENCE-PACKET','Release Evidence Packet SOP','sop','Procedure for generating, reviewing, approving, retaining, and auditing release evidence packets.','audit_compliance','Compliance Engineering','1.0.0','approved','Architecture Review Board',now())
ON CONFLICT (document_code) DO NOTHING;

COMMIT;
