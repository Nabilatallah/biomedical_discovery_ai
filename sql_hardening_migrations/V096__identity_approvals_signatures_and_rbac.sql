-- ============================================================================
-- BioDiscoveryAI Identity, Approvals, Electronic Signatures, and RBAC
-- Migration: V096__identity_approvals_signatures_and_rbac.sql
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS registry.actor_types (
    actor_type_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

INSERT INTO registry.actor_types(actor_type_code, description) VALUES
('human','Human user.'),
('service_account','Service account.'),
('automation','Automation runner.'),
('ai_agent','AI-assisted agent.'),
('external_system','External integrated system.')
ON CONFLICT (actor_type_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS registry.actors (
    actor_id TEXT PRIMARY KEY,
    actor_type TEXT NOT NULL REFERENCES registry.actor_types(actor_type_code),
    display_name TEXT NOT NULL,
    email TEXT,
    external_subject TEXT,
    identity_provider TEXT,
    active BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(identity_provider, external_subject)
);

ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS actor_id TEXT REFERENCES registry.actors(actor_id);
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS actor_id TEXT REFERENCES registry.actors(actor_id);

CREATE TABLE IF NOT EXISTS evidence.approvals (
    approval_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type TEXT NOT NULL,
    related_entity_id TEXT NOT NULL,
    approval_type TEXT NOT NULL CHECK (approval_type IN ('run_finalization','validation_acceptance','artifact_acceptance','release_approval','controlled_correction','deviation_closure','retention_disposition')),
    approval_status TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected','withdrawn','superseded')),
    requested_by TEXT REFERENCES registry.actors(actor_id),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by TEXT REFERENCES registry.actors(actor_id),
    reviewed_at TIMESTAMPTZ,
    approval_reason TEXT NOT NULL,
    decision_rationale TEXT,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_approvals_review_fields CHECK (approval_status IN ('pending','withdrawn') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS evidence.electronic_signatures (
    signature_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type TEXT NOT NULL,
    related_entity_id TEXT NOT NULL,
    approval_id UUID REFERENCES evidence.approvals(approval_id) ON DELETE SET NULL,
    signer_actor_id TEXT NOT NULL REFERENCES registry.actors(actor_id),
    signature_type TEXT NOT NULL REFERENCES registry.signature_types(signature_type_code),
    signature_meaning TEXT NOT NULL CHECK (signature_meaning IN ('reviewed','approved','certified','validated','released','rejected','corrected','witnessed')),
    signature_reason TEXT NOT NULL,
    signed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    signed_record_hash TEXT NOT NULL,
    signature_hash TEXT NOT NULL,
    previous_signature_hash TEXT,
    authentication_context JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE(related_entity_type, related_entity_id, signer_actor_id, signature_meaning)
);

CREATE INDEX IF NOT EXISTS idx_actors_type ON registry.actors(actor_type);
CREATE INDEX IF NOT EXISTS idx_approvals_related_entity ON evidence.approvals(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON evidence.approvals(approval_status);
CREATE INDEX IF NOT EXISTS idx_electronic_signatures_related_entity ON evidence.electronic_signatures(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_electronic_signatures_signer ON evidence.electronic_signatures(signer_actor_id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_evidence_writer') THEN CREATE ROLE bdai_evidence_writer; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_evidence_reader') THEN CREATE ROLE bdai_evidence_reader; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_auditor') THEN CREATE ROLE bdai_auditor; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_reporting_reader') THEN CREATE ROLE bdai_reporting_reader; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_api_service') THEN CREATE ROLE bdai_api_service; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_schema_admin') THEN CREATE ROLE bdai_schema_admin; END IF;
END $$;

GRANT USAGE ON SCHEMA registry, evidence, archive, reporting, signing, api_contract, retention TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader;
GRANT USAGE ON SCHEMA registry, evidence, archive, reporting, signing, api_contract, retention TO bdai_evidence_writer, bdai_api_service;
GRANT USAGE ON SCHEMA governance_admin TO bdai_schema_admin;

GRANT SELECT ON ALL TABLES IN SCHEMA registry, evidence, archive, reporting, signing, api_contract, retention TO bdai_evidence_reader, bdai_auditor, bdai_reporting_reader;
GRANT SELECT, INSERT ON evidence.execution_runs, evidence.audit_events, evidence.execution_steps, evidence.error_events, evidence.dependency_inventory, evidence.provenance_records, evidence.compliance_evidence, evidence.validation_results, evidence.resource_cost_metrics TO bdai_evidence_writer, bdai_api_service;
GRANT SELECT, INSERT ON archive.artifacts TO bdai_evidence_writer, bdai_api_service;
GRANT SELECT, INSERT ON reporting.execution_reports TO bdai_evidence_writer, bdai_api_service;
GRANT SELECT, INSERT ON signing.evidence_snapshots TO bdai_evidence_writer, bdai_api_service;
GRANT SELECT, INSERT, UPDATE ON evidence.approvals TO bdai_api_service;
GRANT SELECT, INSERT ON evidence.electronic_signatures TO bdai_api_service;
GRANT SELECT, INSERT, UPDATE ON registry.actors TO bdai_api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA governance_admin TO bdai_schema_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA evidence GRANT SELECT ON TABLES TO bdai_evidence_reader, bdai_auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA archive GRANT SELECT ON TABLES TO bdai_evidence_reader, bdai_auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA reporting GRANT SELECT ON TABLES TO bdai_reporting_reader, bdai_auditor;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (96, '096', 'Identity, approvals, electronic signatures, and RBAC', 'V096__identity_approvals_signatures_and_rbac.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
