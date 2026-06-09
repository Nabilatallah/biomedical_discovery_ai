-- ============================================================================
-- BioDiscoveryAI Audit Chain Verification and Controlled Corrections
-- Migration: V102__audit_chain_verification_and_controlled_corrections.sql
-- Purpose:
--   Add SQL-native verification for audit hash chains and formalize controlled
--   corrections instead of relying only on session maintenance flags.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION evidence.verify_audit_chain(p_run_id TEXT DEFAULT NULL)
RETURNS TABLE (
    run_id TEXT,
    event_sequence BIGINT,
    audit_event_id UUID,
    previous_hash TEXT,
    expected_previous_hash TEXT,
    event_hash TEXT,
    expected_event_hash TEXT,
    sequence_gap BOOLEAN,
    previous_hash_valid BOOLEAN,
    event_hash_valid BOOLEAN,
    chain_status TEXT
) AS $$
WITH ordered AS (
    SELECT
        a.*,
        lag(a.event_hash) OVER (PARTITION BY a.run_id ORDER BY a.event_sequence) AS lag_hash,
        lag(a.event_sequence) OVER (PARTITION BY a.run_id ORDER BY a.event_sequence) AS lag_sequence
    FROM evidence.audit_events a
    WHERE p_run_id IS NULL OR a.run_id = p_run_id
),
expected AS (
    SELECT
        o.*,
        COALESCE(o.lag_hash, 'GENESIS') AS expected_previous_hash,
        jsonb_build_object(
            'run_id', o.run_id,
            'event_sequence', o.event_sequence,
            'event_type', o.event_type,
            'status', o.status,
            'message', COALESCE(o.message, ''),
            'actor', COALESCE(o.actor, ''),
            'payload', COALESCE(o.payload, '{}'::jsonb),
            'previous_hash', COALESCE(o.lag_hash, 'GENESIS'),
            'created_at', o.created_at
        ) AS expected_canonical_event
    FROM ordered o
)
SELECT
    e.run_id,
    e.event_sequence,
    e.audit_event_id,
    e.previous_hash,
    e.expected_previous_hash,
    e.event_hash,
    evidence.compute_hash(e.expected_canonical_event::TEXT) AS expected_event_hash,
    CASE WHEN e.lag_sequence IS NULL THEN e.event_sequence <> 1 ELSE e.event_sequence <> e.lag_sequence + 1 END AS sequence_gap,
    e.previous_hash = e.expected_previous_hash AS previous_hash_valid,
    e.event_hash = evidence.compute_hash(e.expected_canonical_event::TEXT) AS event_hash_valid,
    CASE
        WHEN (CASE WHEN e.lag_sequence IS NULL THEN e.event_sequence <> 1 ELSE e.event_sequence <> e.lag_sequence + 1 END) THEN 'FAIL_SEQUENCE_GAP'
        WHEN e.previous_hash <> e.expected_previous_hash THEN 'FAIL_PREVIOUS_HASH'
        WHEN e.event_hash <> evidence.compute_hash(e.expected_canonical_event::TEXT) THEN 'FAIL_EVENT_HASH'
        ELSE 'PASS'
    END AS chain_status
FROM expected e
ORDER BY e.run_id, e.event_sequence;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE VIEW evidence.audit_chain_health AS
SELECT
    run_id,
    COUNT(*) AS event_count,
    COUNT(*) FILTER (WHERE chain_status <> 'PASS') AS failed_event_count,
    MIN(event_sequence) AS first_sequence,
    MAX(event_sequence) AS last_sequence,
    CASE WHEN COUNT(*) FILTER (WHERE chain_status <> 'PASS') = 0 THEN 'PASS' ELSE 'FAIL' END AS chain_status
FROM evidence.verify_audit_chain(NULL)
GROUP BY run_id;

CREATE TABLE IF NOT EXISTS evidence.controlled_corrections (
    correction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type TEXT NOT NULL,
    related_entity_id TEXT NOT NULL,
    correction_type TEXT NOT NULL CHECK (correction_type IN ('metadata_correction','status_correction','evidence_annotation','hash_repair','retention_correction','administrative_void','supersession')),
    correction_status TEXT NOT NULL DEFAULT 'pending' CHECK (correction_status IN ('pending','approved','applied','rejected','cancelled')),
    correction_reason TEXT NOT NULL,
    before_record_hash TEXT NOT NULL,
    after_record_hash TEXT,
    approval_id UUID REFERENCES evidence.approvals(approval_id),
    requested_by TEXT REFERENCES registry.actors(actor_id),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_by TEXT REFERENCES registry.actors(actor_id),
    applied_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT chk_controlled_corrections_apply_fields CHECK (correction_status <> 'applied' OR (after_record_hash IS NOT NULL AND applied_by IS NOT NULL AND applied_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_controlled_corrections_entity ON evidence.controlled_corrections(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_controlled_corrections_status ON evidence.controlled_corrections(correction_status);

CREATE OR REPLACE FUNCTION evidence.begin_controlled_correction(p_correction_id UUID)
RETURNS VOID AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT correction_status INTO v_status
    FROM evidence.controlled_corrections
    WHERE correction_id = p_correction_id;

    IF v_status <> 'approved' THEN
        RAISE EXCEPTION 'Controlled correction % is not approved.', p_correction_id;
    END IF;

    PERFORM set_config('bdai.allow_controlled_correction', 'on', true);
    PERFORM set_config('bdai.active_correction_id', p_correction_id::TEXT, true);
END;
$$ LANGUAGE plpgsql;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (102, '102', 'Audit chain verification and controlled corrections', 'V102__audit_chain_verification_and_controlled_corrections.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
