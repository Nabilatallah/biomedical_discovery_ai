\set ON_ERROR_STOP on

DO $$
DECLARE
    missing_count INT;
BEGIN
    SELECT COUNT(*)
    INTO missing_count
    FROM (
        VALUES
            ('registry', 'scripts'),
            ('registry', 'execution_environments'),
            ('evidence', 'execution_runs'),
            ('evidence', 'audit_events'),
            ('archive', 'artifacts'),
            ('container_governance', 'container_images'),
            ('container_governance', 'policy_engines'),
            ('governance_kernel', 'governance_entities'),
            ('governance_kernel', 'governance_events'),
            ('governance_os', 'governance_commands'),
            ('governance_contracts', 'api_services'),
            ('governance_admin', 'schema_migrations')
    ) AS expected(table_schema, table_name)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.tables t
        WHERE t.table_schema = expected.table_schema
          AND t.table_name = expected.table_name
    );

    IF missing_count > 0 THEN
        RAISE EXCEPTION 'Schema validation failed: % expected tables are missing', missing_count;
    END IF;
END $$;

DO $$
DECLARE
    missing_count INT;
BEGIN
    SELECT COUNT(*)
    INTO missing_count
    FROM (
        VALUES
            ('evidence', 'execution_runs', 'run_id'),
            ('evidence', 'execution_runs', 'environment_id'),
            ('evidence', 'execution_runs', 'execution_backend'),
            ('registry', 'execution_environments', 'environment_id'),
            ('registry', 'script_cli_options', 'script_id'),
            ('archive', 'artifacts', 'sha256'),
            ('governance_admin', 'schema_migrations', 'version')
    ) AS expected(table_schema, table_name, column_name)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns c
        WHERE c.table_schema = expected.table_schema
          AND c.table_name = expected.table_name
          AND c.column_name = expected.column_name
    );

    IF missing_count > 0 THEN
        RAISE EXCEPTION 'Schema validation failed: % expected columns are missing', missing_count;
    END IF;
END $$;

DO $$
DECLARE
    environment_count INT;
    contract_count INT;
BEGIN
    SELECT COUNT(*)
    INTO environment_count
    FROM registry.execution_environments
    WHERE environment_id IN (
        'local-dev',
        'explorer-hpc-apptainer',
        'explorer-hpc-gpu-apptainer',
        'aws-batch-docker'
    );

    IF environment_count < 4 THEN
        RAISE EXCEPTION 'Seed validation failed: expected execution environment reference records are missing';
    END IF;

    SELECT COUNT(*)
    INTO contract_count
    FROM registry.script_cli_options
    WHERE script_id = 'B001_01';

    IF contract_count < 5 THEN
        RAISE EXCEPTION 'Seed validation failed: expected B001_01 CLI contract records are missing';
    END IF;
END $$;

SELECT
    'governance bundle validation PASS' AS status,
    COUNT(*) AS flyway_migrations_recorded
FROM flyway_schema_history
WHERE success = true
  AND type <> 'SCHEMA';
