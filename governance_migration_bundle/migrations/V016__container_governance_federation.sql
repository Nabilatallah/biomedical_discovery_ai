-- ============================================================================
-- BioDiscoveryAI Container Governance Federation
-- Migration: V018__container_governance_federation.sql
-- Purpose:
--   Federate container governance across local, HPC, cloud, registry, CI/CD,
--   and external evidence systems while preserving immutable lineage, trust,
--   sync status, conflict resolution, data residency, and cross-site auditability.
--
-- Dependencies:
--   V011, V015, V016
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- ============================================================================
-- 1. Federated Nodes and Trust
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.federation_nodes (
    federation_node_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_name                TEXT NOT NULL UNIQUE,
    node_type                TEXT NOT NULL CHECK (node_type IN ('local_dev', 'hpc', 'cloud', 'ci_cd', 'registry', 'artifact_store', 'compliance_vault', 'external_partner')),
    node_uri                 TEXT NOT NULL,
    owning_organization      TEXT NOT NULL,
    environment_id           UUID REFERENCES container_governance.execution_environments(environment_id),
    trust_level              TEXT NOT NULL CHECK (trust_level IN ('untrusted', 'restricted', 'trusted', 'regulated_trusted')),
    data_residency_region    TEXT NOT NULL,
    allowed_data_classes     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    inbound_sync_allowed     BOOLEAN NOT NULL DEFAULT false,
    outbound_sync_allowed    BOOLEAN NOT NULL DEFAULT false,
    approval_status          TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected', 'retired')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.federation_trust_agreements (
    trust_agreement_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    target_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    agreement_name           TEXT NOT NULL,
    agreement_description    TEXT NOT NULL,
    allowed_entity_types     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    allowed_operations       TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    signature_required       BOOLEAN NOT NULL DEFAULT true,
    encryption_required      BOOLEAN NOT NULL DEFAULT true,
    approval_required        BOOLEAN NOT NULL DEFAULT true,
    effective_from           DATE NOT NULL DEFAULT CURRENT_DATE,
    expires_on               DATE,
    status                   TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'expired', 'revoked')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ,
    UNIQUE(source_node_id, target_node_id, agreement_name)
);

-- ============================================================================
-- 2. Federated Object Identity and Sync
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.federated_object_mappings (
    object_mapping_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_entity_type        TEXT NOT NULL,
    local_entity_id          TEXT NOT NULL,
    remote_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    remote_entity_type       TEXT NOT NULL,
    remote_entity_id         TEXT NOT NULL,
    remote_uri               TEXT,
    remote_sha256            TEXT,
    mapping_status           TEXT NOT NULL DEFAULT 'active' CHECK (mapping_status IN ('active', 'stale', 'conflict', 'retired')),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(local_entity_type, local_entity_id, remote_node_id, remote_entity_type, remote_entity_id)
);

CREATE TABLE IF NOT EXISTS container_governance.federation_sync_jobs (
    sync_job_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    target_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    sync_direction           TEXT NOT NULL CHECK (sync_direction IN ('push', 'pull', 'bidirectional')),
    sync_scope               TEXT NOT NULL,
    sync_filter              JSONB NOT NULL DEFAULT '{}',
    requested_by             TEXT NOT NULL,
    requested_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    status                   TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'approved', 'running', 'completed', 'failed', 'cancelled')),
    approved_by              TEXT,
    approved_at              TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.federation_sync_runs (
    sync_run_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sync_job_id              UUID NOT NULL REFERENCES container_governance.federation_sync_jobs(sync_job_id),
    started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at              TIMESTAMPTZ,
    run_status               TEXT NOT NULL DEFAULT 'running' CHECK (run_status IN ('running', 'passed', 'failed', 'partial', 'cancelled')),
    records_examined         BIGINT NOT NULL DEFAULT 0,
    records_created          BIGINT NOT NULL DEFAULT 0,
    records_updated          BIGINT NOT NULL DEFAULT 0,
    records_skipped          BIGINT NOT NULL DEFAULT 0,
    records_conflicted       BIGINT NOT NULL DEFAULT 0,
    sync_manifest_uri        TEXT,
    sync_manifest_sha256     TEXT,
    failure_reason           TEXT
);

-- ============================================================================
-- 3. Conflict Resolution and Federation Evidence
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.federation_conflicts (
    federation_conflict_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sync_run_id              UUID REFERENCES container_governance.federation_sync_runs(sync_run_id),
    local_entity_type        TEXT NOT NULL,
    local_entity_id          TEXT NOT NULL,
    remote_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    remote_entity_type       TEXT NOT NULL,
    remote_entity_id         TEXT NOT NULL,
    conflict_type            TEXT NOT NULL CHECK (conflict_type IN ('hash_mismatch', 'version_mismatch', 'approval_mismatch', 'signature_mismatch', 'policy_mismatch', 'missing_dependency')),
    conflict_description     TEXT NOT NULL,
    local_state              JSONB,
    remote_state             JSONB,
    resolution_strategy      TEXT CHECK (resolution_strategy IN ('accept_local', 'accept_remote', 'manual_merge', 'reject_remote', 'supersede')),
    resolution_notes         TEXT,
    resolved_by              TEXT,
    resolved_at              TIMESTAMPTZ,
    status                   TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved', 'accepted_risk', 'cancelled')),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS container_governance.federated_evidence_imports (
    federated_evidence_import_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_node_id           UUID NOT NULL REFERENCES container_governance.federation_nodes(federation_node_id),
    evidence_id              UUID REFERENCES container_governance.container_evidence(evidence_id),
    artifact_id              UUID REFERENCES container_governance.artifacts(artifact_id),
    remote_evidence_uri      TEXT NOT NULL,
    remote_evidence_sha256   TEXT NOT NULL,
    signature_verified       BOOLEAN NOT NULL DEFAULT false,
    provenance_verified      BOOLEAN NOT NULL DEFAULT false,
    import_status            TEXT NOT NULL DEFAULT 'pending' CHECK (import_status IN ('pending', 'accepted', 'rejected', 'quarantined')),
    imported_by              TEXT NOT NULL,
    imported_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    rejection_reason         TEXT
);

-- ============================================================================
-- 4. Data Residency and Export Controls
-- ============================================================================

CREATE TABLE IF NOT EXISTS container_governance.federation_export_controls (
    export_control_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name                TEXT NOT NULL UNIQUE,
    rule_description         TEXT NOT NULL,
    source_region            TEXT NOT NULL,
    target_region            TEXT NOT NULL,
    entity_type              TEXT NOT NULL,
    data_classification      TEXT NOT NULL,
    export_allowed           BOOLEAN NOT NULL DEFAULT false,
    approval_required        BOOLEAN NOT NULL DEFAULT true,
    legal_basis              TEXT NOT NULL,
    active                   BOOLEAN NOT NULL DEFAULT true,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION container_governance.is_federation_allowed(p_source_node UUID, p_target_node UUID, p_entity_type TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.federation_trust_agreements a
        WHERE a.source_node_id = p_source_node
          AND a.target_node_id = p_target_node
          AND a.status = 'active'
          AND p_entity_type = ANY(a.allowed_entity_types)
          AND (a.expires_on IS NULL OR a.expires_on >= CURRENT_DATE)
    ) INTO result;
    RETURN COALESCE(result, false);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION container_governance.prevent_untrusted_federation_sync()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT container_governance.is_federation_allowed(NEW.source_node_id, NEW.target_node_id, NEW.sync_scope) THEN
        RAISE EXCEPTION 'Federation sync from % to % for scope % is not covered by an active trust agreement.', NEW.source_node_id, NEW.target_node_id, NEW.sync_scope;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_untrusted_federation_sync ON container_governance.federation_sync_jobs;
CREATE TRIGGER trg_prevent_untrusted_federation_sync
BEFORE INSERT OR UPDATE ON container_governance.federation_sync_jobs
FOR EACH ROW
EXECUTE FUNCTION container_governance.prevent_untrusted_federation_sync();

-- ============================================================================
-- 5. Views and Indexes
-- ============================================================================

CREATE OR REPLACE VIEW container_governance.v_federation_health AS
SELECT
    n.federation_node_id,
    n.node_name,
    n.node_type,
    n.trust_level,
    n.approval_status,
    COUNT(DISTINCT sj.sync_job_id) AS sync_job_count,
    COUNT(DISTINCT sr.sync_run_id) FILTER (WHERE sr.run_status = 'failed') AS failed_sync_runs,
    COUNT(DISTINCT c.federation_conflict_id) FILTER (WHERE c.status = 'open') AS open_conflicts
FROM container_governance.federation_nodes n
LEFT JOIN container_governance.federation_sync_jobs sj ON n.federation_node_id IN (sj.source_node_id, sj.target_node_id)
LEFT JOIN container_governance.federation_sync_runs sr ON sj.sync_job_id = sr.sync_job_id
LEFT JOIN container_governance.federation_conflicts c ON n.federation_node_id = c.remote_node_id
GROUP BY n.federation_node_id, n.node_name, n.node_type, n.trust_level, n.approval_status;

CREATE INDEX IF NOT EXISTS idx_federation_nodes_type ON container_governance.federation_nodes(node_type, approval_status);
CREATE INDEX IF NOT EXISTS idx_federated_object_mappings_local ON container_governance.federated_object_mappings(local_entity_type, local_entity_id);
CREATE INDEX IF NOT EXISTS idx_federation_sync_jobs_status ON container_governance.federation_sync_jobs(status, requested_at);
CREATE INDEX IF NOT EXISTS idx_federation_conflicts_status ON container_governance.federation_conflicts(status, created_at);
CREATE INDEX IF NOT EXISTS idx_federated_evidence_imports_status ON container_governance.federated_evidence_imports(import_status, imported_at);

COMMIT;
