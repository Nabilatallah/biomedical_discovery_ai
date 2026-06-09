-- ============================================================================
-- BioDiscoveryAI Partition Maintenance and Integrity
-- Migration: V104__partition_maintenance_and_integrity.sql
-- Purpose:
--   Add partition metadata, precreation helpers, missing-partition detection,
--   and partition health views for high-growth evidence tables.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS governance_admin.partition_maintenance_policies (
    partition_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_schema TEXT NOT NULL,
    parent_table TEXT NOT NULL,
    partition_column TEXT NOT NULL DEFAULT 'created_at',
    partition_strategy TEXT NOT NULL DEFAULT 'range_monthly' CHECK (partition_strategy = 'range_monthly'),
    precreate_months INT NOT NULL DEFAULT 24 CHECK (precreate_months > 0),
    retention_months INT CHECK (retention_months IS NULL OR retention_months > 0),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(parent_schema, parent_table)
);

INSERT INTO governance_admin.partition_maintenance_policies (
    parent_schema, parent_table, partition_column, precreate_months, retention_months
)
VALUES
('evidence','audit_events','created_at',36,84),
('evidence','execution_steps','created_at',36,84),
('evidence','error_events','created_at',36,84),
('archive','artifacts','created_at',36,84),
('reporting','execution_reports','created_at',36,84)
ON CONFLICT (parent_schema, parent_table) DO NOTHING;

CREATE OR REPLACE FUNCTION governance_admin.precreate_monthly_partitions(p_months_ahead INT DEFAULT NULL)
RETURNS TABLE(parent_table TEXT, partition_name TEXT, partition_start DATE, partition_end DATE, action_taken TEXT) AS $$
DECLARE
    p RECORD;
    v_months INT;
    v_start DATE;
    v_end DATE;
    v_partition_name TEXT;
BEGIN
    FOR p IN SELECT * FROM governance_admin.partition_maintenance_policies WHERE active = true LOOP
        v_months := COALESCE(p_months_ahead, p.precreate_months);
        FOR v_start IN SELECT generate_series(date_trunc('month', now())::DATE, (date_trunc('month', now()) + make_interval(months => v_months))::DATE, INTERVAL '1 month')::DATE LOOP
            v_end := (v_start + INTERVAL '1 month')::DATE;
            v_partition_name := p.parent_table || '_' || to_char(v_start, 'YYYY_MM');
            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                p.parent_schema, v_partition_name, p.parent_schema, p.parent_table, v_start, v_end
            );
            parent_table := p.parent_schema || '.' || p.parent_table;
            partition_name := p.parent_schema || '.' || v_partition_name;
            partition_start := v_start;
            partition_end := v_end;
            action_taken := 'ensured';
            RETURN NEXT;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW governance_admin.partition_health AS
SELECT
    p.parent_schema,
    p.parent_table,
    c.relname AS partition_name,
    p.precreate_months,
    p.retention_months,
    pg_total_relation_size(format('%I.%I', n.nspname, c.relname)::regclass) AS total_bytes
FROM governance_admin.partition_maintenance_policies p
JOIN pg_inherits i ON i.inhparent = format('%I.%I', p.parent_schema, p.parent_table)::regclass
JOIN pg_class c ON c.oid = i.inhrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
ORDER BY p.parent_schema, p.parent_table, c.relname;

CREATE OR REPLACE VIEW governance_admin.partition_policy_coverage AS
SELECT
    p.parent_schema,
    p.parent_table,
    to_regclass(format('%I.%I', p.parent_schema, p.parent_table)) IS NOT NULL AS parent_exists,
    COALESCE(COUNT(h.partition_name), 0) AS partition_count
FROM governance_admin.partition_maintenance_policies p
LEFT JOIN governance_admin.partition_health h
  ON h.parent_schema = p.parent_schema AND h.parent_table = p.parent_table
GROUP BY p.parent_schema, p.parent_table;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (104, '104', 'Partition maintenance and integrity', 'V104__partition_maintenance_and_integrity.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
