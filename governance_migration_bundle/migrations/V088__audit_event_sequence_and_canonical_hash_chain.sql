-- ============================================================================
-- BioDiscoveryAI Stronger Audit Event Hash Chain
-- Migration: V094__audit_event_sequence_and_canonical_hash_chain.sql
-- ============================================================================

BEGIN;

SET LOCAL bdai.allow_append_only_maintenance = 'on';

ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS event_sequence BIGINT;
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS canonical_event JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE evidence.audit_events ADD COLUMN IF NOT EXISTS hash_algorithm TEXT NOT NULL DEFAULT 'sha256-canonical-json-v1';

WITH numbered AS (
    SELECT audit_event_id,
           row_number() OVER (PARTITION BY run_id ORDER BY created_at, audit_event_id)::BIGINT AS seq
    FROM evidence.audit_events
    WHERE event_sequence IS NULL
)
UPDATE evidence.audit_events a
SET event_sequence = n.seq
FROM numbered n
WHERE a.audit_event_id = n.audit_event_id;

UPDATE evidence.audit_events
SET canonical_event = jsonb_build_object(
    'run_id', run_id,
    'event_sequence', event_sequence,
    'event_type', event_type,
    'status', status,
    'message', COALESCE(message, ''),
    'actor', COALESCE(actor, ''),
    'payload', COALESCE(payload, '{}'::jsonb),
    'previous_hash', COALESCE(previous_hash, 'GENESIS'),
    'created_at', created_at
)
WHERE canonical_event = '{}'::jsonb;

ALTER TABLE evidence.audit_events ALTER COLUMN event_sequence SET NOT NULL;
ALTER TABLE evidence.audit_events DROP CONSTRAINT IF EXISTS uq_audit_events_run_sequence;
ALTER TABLE evidence.audit_events ADD CONSTRAINT uq_audit_events_run_sequence UNIQUE (run_id, event_sequence);
ALTER TABLE evidence.audit_events DROP CONSTRAINT IF EXISTS chk_audit_events_sequence_positive;
ALTER TABLE evidence.audit_events ADD CONSTRAINT chk_audit_events_sequence_positive CHECK (event_sequence > 0) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_audit_events_run_sequence ON evidence.audit_events(run_id, event_sequence);
CREATE INDEX IF NOT EXISTS idx_audit_events_hash_algorithm ON evidence.audit_events(hash_algorithm);

CREATE OR REPLACE FUNCTION evidence.audit_events_hash_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_previous_hash TEXT;
    v_next_sequence BIGINT;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(NEW.run_id));

    IF NEW.event_sequence IS NULL THEN
        SELECT COALESCE(MAX(event_sequence), 0) + 1
        INTO v_next_sequence
        FROM evidence.audit_events
        WHERE run_id = NEW.run_id;
        NEW.event_sequence := v_next_sequence;
    END IF;

    SELECT event_hash INTO v_previous_hash
    FROM evidence.audit_events
    WHERE run_id = NEW.run_id
      AND event_sequence < NEW.event_sequence
    ORDER BY event_sequence DESC
    LIMIT 1;

    NEW.previous_hash := COALESCE(v_previous_hash, 'GENESIS');
    NEW.hash_algorithm := COALESCE(NULLIF(NEW.hash_algorithm, ''), 'sha256-canonical-json-v1');
    NEW.canonical_event := jsonb_build_object(
        'run_id', NEW.run_id,
        'event_sequence', NEW.event_sequence,
        'event_type', NEW.event_type,
        'status', NEW.status,
        'message', COALESCE(NEW.message, ''),
        'actor', COALESCE(NEW.actor, ''),
        'payload', COALESCE(NEW.payload, '{}'::jsonb),
        'previous_hash', NEW.previous_hash,
        'created_at', COALESCE(NEW.created_at, now())
    );
    NEW.event_hash := evidence.compute_hash(NEW.canonical_event::TEXT);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_events_hash ON evidence.audit_events;
CREATE TRIGGER trg_audit_events_hash
BEFORE INSERT ON evidence.audit_events
FOR EACH ROW EXECUTE FUNCTION evidence.audit_events_hash_trigger();

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (94, '094', 'Audit event sequence and canonical hash chain', 'V094__audit_event_sequence_and_canonical_hash_chain.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
