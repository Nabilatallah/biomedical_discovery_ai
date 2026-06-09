-- ============================================================================
-- BioDiscoveryAI DDL Audit and Privileged Operation Logging
-- Migration: V103__ddl_audit_and_privileged_operation_logging.sql
-- Purpose:
--   Capture schema/DDL activity and privileged database events using event
--   triggers for inspection readiness and change-control evidence.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS governance_admin.ddl_audit_events (
    ddl_audit_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    command_tag TEXT,
    object_type TEXT,
    schema_name TEXT,
    object_identity TEXT,
    actor TEXT NOT NULL DEFAULT current_user,
    database_name TEXT NOT NULL DEFAULT current_database(),
    client_addr INET DEFAULT inet_client_addr(),
    txid BIGINT NOT NULL DEFAULT txid_current(),
    event_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION governance_admin.capture_ddl_command_end()
RETURNS event_trigger AS $$
DECLARE
    cmd RECORD;
BEGIN
    FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO governance_admin.ddl_audit_events (
            event_type, command_tag, object_type, schema_name, object_identity, event_payload
        )
        VALUES (
            'ddl_command_end',
            cmd.command_tag,
            cmd.object_type,
            cmd.schema_name,
            cmd.object_identity,
            jsonb_build_object('classid', cmd.classid::TEXT, 'objid', cmd.objid::TEXT, 'objsubid', cmd.objsubid)
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION governance_admin.capture_sql_drop()
RETURNS event_trigger AS $$
DECLARE
    obj RECORD;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects() LOOP
        INSERT INTO governance_admin.ddl_audit_events (
            event_type, command_tag, object_type, schema_name, object_identity, event_payload
        )
        VALUES (
            'sql_drop',
            TG_TAG,
            obj.object_type,
            obj.schema_name,
            obj.object_identity,
            jsonb_build_object('is_temporary', obj.is_temporary, 'original', obj.original, 'normal', obj.normal)
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP EVENT TRIGGER IF EXISTS trg_bdai_ddl_command_end;
CREATE EVENT TRIGGER trg_bdai_ddl_command_end
ON ddl_command_end
EXECUTE FUNCTION governance_admin.capture_ddl_command_end();

DROP EVENT TRIGGER IF EXISTS trg_bdai_sql_drop;
CREATE EVENT TRIGGER trg_bdai_sql_drop
ON sql_drop
EXECUTE FUNCTION governance_admin.capture_sql_drop();

CREATE INDEX IF NOT EXISTS idx_ddl_audit_events_created ON governance_admin.ddl_audit_events(created_at);
CREATE INDEX IF NOT EXISTS idx_ddl_audit_events_object ON governance_admin.ddl_audit_events(schema_name, object_identity);
CREATE INDEX IF NOT EXISTS idx_ddl_audit_events_actor ON governance_admin.ddl_audit_events(actor);

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (103, '103', 'DDL audit and privileged operation logging', 'V103__ddl_audit_and_privileged_operation_logging.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
