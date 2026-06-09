CREATE OR REPLACE FUNCTION evidence.compute_hash(payload TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN encode(digest(payload, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION evidence.audit_events_hash_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_previous_hash TEXT;
    v_payload TEXT;
BEGIN
    SELECT event_hash INTO v_previous_hash
    FROM evidence.audit_events
    WHERE run_id = NEW.run_id
    ORDER BY created_at DESC
    LIMIT 1;

    NEW.previous_hash := COALESCE(v_previous_hash, 'GENESIS');

    v_payload := NEW.run_id || NEW.event_type || NEW.status ||
                 COALESCE(NEW.message, '') || COALESCE(NEW.actor, '') ||
                 COALESCE(NEW.payload::TEXT, '') || NEW.previous_hash;

    NEW.event_hash := evidence.compute_hash(v_payload);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_events_hash ON evidence.audit_events;
CREATE TRIGGER trg_audit_events_hash
BEFORE INSERT ON evidence.audit_events
FOR EACH ROW
EXECUTE FUNCTION evidence.audit_events_hash_trigger();
