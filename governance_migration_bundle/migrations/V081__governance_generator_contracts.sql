-- ============================================================================
-- BioDiscoveryAI Governance Generator Contracts
-- Migration: V087__governance_generator_contracts.sql
-- Purpose:
--   Define contracts for generators that create Dockerfiles, Apptainer
--   definitions, Nextflow pipelines, CI/CD workflows, evidence packets,
--   dashboards, API clients, and audit reports from approved SQL records.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_contracts;

CREATE TABLE IF NOT EXISTS governance_contracts.generators (
    generator_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generator_code TEXT NOT NULL UNIQUE,
    generator_name TEXT NOT NULL,
    generator_description TEXT NOT NULL,
    generator_type TEXT NOT NULL CHECK (
        generator_type IN ('dockerfile','apptainer','nextflow','cicd','evidence_packet','dashboard','api_client','audit_report','sop','other')
    ),
    generator_owner TEXT NOT NULL,
    current_version TEXT NOT NULL,
    source_repo TEXT,
    source_path TEXT,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','deprecated','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.generator_contracts (
    generator_contract_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generator_id UUID NOT NULL REFERENCES governance_contracts.generators(generator_id),
    contract_version TEXT NOT NULL,
    input_contract JSONB NOT NULL,
    output_contract JSONB NOT NULL,
    deterministic_output_required BOOLEAN NOT NULL DEFAULT true,
    source_of_truth_schema TEXT NOT NULL,
    source_of_truth_tables TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    manual_edit_allowed BOOLEAN NOT NULL DEFAULT false,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','deprecated','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    UNIQUE(generator_id, contract_version)
);

CREATE TABLE IF NOT EXISTS governance_contracts.generator_runs (
    generator_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generator_id UUID NOT NULL REFERENCES governance_contracts.generators(generator_id),
    generator_contract_id UUID REFERENCES governance_contracts.generator_contracts(generator_contract_id),
    run_name TEXT NOT NULL,
    run_context JSONB NOT NULL DEFAULT '{}',
    source_record_references JSONB NOT NULL DEFAULT '[]',
    output_artifact_type TEXT NOT NULL,
    output_artifact_uri TEXT,
    output_artifact_sha256 TEXT,
    run_status TEXT NOT NULL DEFAULT 'started'
        CHECK (run_status IN ('started','passed','failed','cancelled')),
    generated_by TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS governance_contracts.generator_validation_results (
    generator_validation_result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generator_run_id UUID NOT NULL REFERENCES governance_contracts.generator_runs(generator_run_id),
    validation_name TEXT NOT NULL,
    validation_description TEXT NOT NULL,
    validation_status TEXT NOT NULL CHECK (validation_status IN ('pass','fail','warning','not_applicable')),
    validation_summary TEXT NOT NULL,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION governance_contracts.prevent_manual_generated_artifact_approval()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.manual_edit_allowed = true AND NEW.approval_status = 'approved' THEN
        RAISE EXCEPTION 'Generator contract % cannot be approved with manual_edit_allowed=true', NEW.generator_contract_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_manual_generated_artifact_approval
ON governance_contracts.generator_contracts;

CREATE TRIGGER trg_prevent_manual_generated_artifact_approval
BEFORE INSERT OR UPDATE ON governance_contracts.generator_contracts
FOR EACH ROW
EXECUTE FUNCTION governance_contracts.prevent_manual_generated_artifact_approval();

INSERT INTO governance_contracts.generators (
    generator_code, generator_name, generator_description, generator_type, generator_owner, current_version, approval_status, approved_by, approved_at
)
VALUES
('DOCKERFILE_GENERATOR','Dockerfile Generator','Generates immutable Dockerfiles from approved package, image, module, and runtime-policy records.','dockerfile','Platform Engineering','1.0.0','approved','Architecture Review Board',now()),
('APPTAINER_GENERATOR','Apptainer Definition Generator','Generates Apptainer definition files from the same source records used for Dockerfiles.','apptainer','Platform Engineering','1.0.0','approved','Architecture Review Board',now()),
('EVIDENCE_PACKET_GENERATOR','Evidence Packet Generator','Generates audit-ready release evidence packets from approved records and artifacts.','evidence_packet','Compliance Engineering','1.0.0','approved','Architecture Review Board',now())
ON CONFLICT (generator_code) DO NOTHING;

COMMIT;
