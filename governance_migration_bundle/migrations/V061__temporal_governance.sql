-- ============================================================================
-- BioDiscoveryAI Temporal Governance
-- Migration: V063__temporal_governance.sql
-- Purpose:
--   Add temporal and bitemporal governance support, enabling reconstruction of
--   historical state, effective dating, valid-time/system-time tracking, and
--   audit-ready point-in-time governance queries.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_kernel;

CREATE TABLE IF NOT EXISTS governance_kernel.temporal_snapshots (
    temporal_snapshot_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_name           TEXT NOT NULL,
    snapshot_description    TEXT NOT NULL,
    snapshot_scope          TEXT NOT NULL,
    snapshot_time           TIMESTAMPTZ NOT NULL,
    created_by              TEXT NOT NULL DEFAULT current_user,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    artifact_uri            TEXT,
    artifact_sha256         TEXT,
    UNIQUE(snapshot_name, snapshot_time)
);

CREATE TABLE IF NOT EXISTS governance_kernel.entity_state_history (
    entity_state_history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id               UUID NOT NULL REFERENCES governance_kernel.governance_entities(entity_id),
    state_name              TEXT NOT NULL,
    state_value             TEXT NOT NULL,
    state_payload           JSONB NOT NULL DEFAULT '{}',
    valid_from              TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_to                TIMESTAMPTZ,
    system_from             TIMESTAMPTZ NOT NULL DEFAULT now(),
    system_to               TIMESTAMPTZ,
    changed_by              TEXT NOT NULL DEFAULT current_user,
    change_reason           TEXT NOT NULL,
    evidence_uri            TEXT,
    evidence_sha256         TEXT
);

CREATE TABLE IF NOT EXISTS governance_kernel.relationship_state_history (
    relationship_state_history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_relationship_id     UUID NOT NULL REFERENCES governance_kernel.entity_relationships(entity_relationship_id),
    state_name                 TEXT NOT NULL,
    state_value                TEXT NOT NULL,
    state_payload              JSONB NOT NULL DEFAULT '{}',
    valid_from                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_to                   TIMESTAMPTZ,
    system_from                TIMESTAMPTZ NOT NULL DEFAULT now(),
    system_to                  TIMESTAMPTZ,
    changed_by                 TEXT NOT NULL DEFAULT current_user,
    change_reason              TEXT NOT NULL,
    evidence_uri               TEXT,
    evidence_sha256            TEXT
);

CREATE TABLE IF NOT EXISTS governance_kernel.temporal_reconstruction_requests (
    reconstruction_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requested_as_of_time      TIMESTAMPTZ NOT NULL,
    reconstruction_scope      TEXT NOT NULL,
    requested_by              TEXT NOT NULL DEFAULT current_user,
    requested_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    status                    TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested','running','completed','failed','cancelled')),
    result_uri                TEXT,
    result_sha256             TEXT
);

CREATE OR REPLACE VIEW governance_kernel.v_current_entity_state AS
SELECT
    ge.entity_id,
    ge.enterprise_object_id,
    ge.canonical_name,
    ge.status,
    ge.criticality,
    ge.owner,
    ge.updated_at
FROM governance_kernel.governance_entities ge
WHERE ge.status <> 'archived';

CREATE OR REPLACE VIEW governance_kernel.v_active_entity_relationships AS
SELECT
    *
FROM governance_kernel.v_entity_relationship_graph
WHERE effective_to IS NULL OR effective_to > now();

CREATE INDEX IF NOT EXISTS idx_entity_state_history_entity
ON governance_kernel.entity_state_history(entity_id);

CREATE INDEX IF NOT EXISTS idx_entity_state_history_valid_time
ON governance_kernel.entity_state_history(valid_from, valid_to);

CREATE INDEX IF NOT EXISTS idx_relationship_state_history_relationship
ON governance_kernel.relationship_state_history(entity_relationship_id);

CREATE INDEX IF NOT EXISTS idx_temporal_snapshots_time
ON governance_kernel.temporal_snapshots(snapshot_time);

COMMIT;
