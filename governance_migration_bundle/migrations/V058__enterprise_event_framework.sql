-- ============================================================================
-- BioDiscoveryAI Enterprise Event Framework
-- Migration: V060__enterprise_event_framework.sql
-- Purpose:
--   Create a universal event timeline for all governance domains, with event
--   types, immutable event records, event hash chain, causal links, and evidence.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_kernel;

CREATE TABLE IF NOT EXISTS governance_kernel.event_types (
    event_type_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type_code         TEXT NOT NULL UNIQUE,
    event_type_name         TEXT NOT NULL,
    event_type_description  TEXT NOT NULL,
    category                TEXT NOT NULL,
    regulated_event         BOOLEAN NOT NULL DEFAULT false,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_kernel.governance_events (
    governance_event_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type_id           UUID NOT NULL REFERENCES governance_kernel.event_types(event_type_id),
    entity_id               UUID REFERENCES governance_kernel.governance_entities(entity_id),
    enterprise_object_id    TEXT,
    event_time              TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor                   TEXT NOT NULL,
    action                  TEXT NOT NULL,
    event_summary           TEXT NOT NULL,
    event_details           JSONB NOT NULL DEFAULT '{}',
    source_system           TEXT NOT NULL DEFAULT 'postgresql',
    source_schema           TEXT,
    source_table            TEXT,
    source_primary_key      TEXT,
    previous_event_hash     TEXT,
    event_hash              TEXT NOT NULL DEFAULT 'pending',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_kernel.event_causal_links (
    event_causal_link_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cause_event_id          UUID NOT NULL REFERENCES governance_kernel.governance_events(governance_event_id),
    effect_event_id         UUID NOT NULL REFERENCES governance_kernel.governance_events(governance_event_id),
    link_type               TEXT NOT NULL CHECK (link_type IN ('caused','triggered','superseded','remediated','approved','blocked')),
    link_summary            TEXT NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(cause_event_id, effect_event_id, link_type)
);

CREATE TABLE IF NOT EXISTS governance_kernel.event_evidence_links (
    event_evidence_link_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_event_id     UUID NOT NULL REFERENCES governance_kernel.governance_events(governance_event_id),
    evidence_entity_type    TEXT NOT NULL,
    evidence_entity_id      TEXT NOT NULL,
    evidence_uri            TEXT,
    evidence_sha256         TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION governance_kernel.compute_governance_event_hash()
RETURNS TRIGGER AS $$
DECLARE
    last_hash TEXT;
    payload TEXT;
BEGIN
    SELECT event_hash
    INTO last_hash
    FROM governance_kernel.governance_events
    ORDER BY event_time DESC, created_at DESC
    LIMIT 1;

    NEW.previous_event_hash := last_hash;

    payload :=
        COALESCE(NEW.event_time::TEXT,'') ||
        COALESCE(NEW.actor,'') ||
        COALESCE(NEW.action,'') ||
        COALESCE(NEW.event_summary,'') ||
        COALESCE(NEW.event_details::TEXT,'') ||
        COALESCE(NEW.previous_event_hash,'');

    NEW.event_hash := encode(digest(payload, 'sha256'), 'hex');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_compute_governance_event_hash ON governance_kernel.governance_events;
CREATE TRIGGER trg_compute_governance_event_hash
BEFORE INSERT ON governance_kernel.governance_events
FOR EACH ROW
EXECUTE FUNCTION governance_kernel.compute_governance_event_hash();

CREATE OR REPLACE FUNCTION governance_kernel.prevent_governance_event_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Governance events are immutable and cannot be modified or deleted';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_governance_event_mutation ON governance_kernel.governance_events;
CREATE TRIGGER trg_prevent_governance_event_mutation
BEFORE UPDATE OR DELETE ON governance_kernel.governance_events
FOR EACH ROW
EXECUTE FUNCTION governance_kernel.prevent_governance_event_mutation();

INSERT INTO governance_kernel.event_types (
    event_type_code, event_type_name, event_type_description, category, regulated_event
)
VALUES
('CREATED','Created','Governed object was created.','lifecycle',true),
('APPROVED','Approved','Governed object was approved.','approval',true),
('REJECTED','Rejected','Governed object was rejected.','approval',true),
('RELEASED','Released','Governed object was released for use.','release',true),
('EXECUTED','Executed','Governed executable object was executed.','runtime',true),
('RETIRED','Retired','Governed object was retired.','lifecycle',true),
('INCIDENT_OPENED','Incident Opened','Incident opened against governed object.','incident',true),
('CAPA_OPENED','CAPA Opened','CAPA opened against governed object.','quality',true)
ON CONFLICT (event_type_code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_governance_events_entity
ON governance_kernel.governance_events(entity_id);

CREATE INDEX IF NOT EXISTS idx_governance_events_time
ON governance_kernel.governance_events(event_time);

COMMIT;
