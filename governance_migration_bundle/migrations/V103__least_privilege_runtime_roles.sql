-- Repo-local operational hardening layer.
-- Separates migration ownership from API runtime, read-only, audit, and
-- break-glass personas. The API connects as the configured database user and
-- immediately SET ROLEs into bdai_app_runtime or bdai_readonly.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_migrator') THEN
        CREATE ROLE bdai_migrator NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_app_runtime') THEN
        CREATE ROLE bdai_app_runtime NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_readonly') THEN
        CREATE ROLE bdai_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_auditor') THEN
        CREATE ROLE bdai_auditor NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bdai_break_glass') THEN
        CREATE ROLE bdai_break_glass NOLOGIN;
    END IF;
END $$;

GRANT bdai_migrator TO CURRENT_USER;
GRANT bdai_app_runtime TO CURRENT_USER;
GRANT bdai_readonly TO CURRENT_USER;
GRANT bdai_auditor TO CURRENT_USER;
GRANT bdai_break_glass TO CURRENT_USER;

DO $$
DECLARE
    target_schema TEXT;
BEGIN
    FOREACH target_schema IN ARRAY ARRAY[
        'registry',
        'evidence',
        'archive',
        'reporting',
        'retention',
        'signing',
        'audit',
        'api_contract',
        'container_governance',
        'governance_kernel',
        'governance_platform',
        'governance_os',
        'governance_contracts',
        'governance_admin'
    ]
    LOOP
        IF EXISTS (SELECT 1 FROM information_schema.schemata s WHERE s.schema_name = target_schema) THEN
            EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC', target_schema);
            EXECUTE format('GRANT USAGE ON SCHEMA %I TO bdai_readonly, bdai_app_runtime, bdai_auditor, bdai_break_glass', target_schema);
            EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO bdai_readonly, bdai_app_runtime, bdai_auditor, bdai_break_glass', target_schema);
            EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO bdai_readonly, bdai_app_runtime, bdai_auditor', target_schema);
        END IF;
    END LOOP;
END $$;

GRANT INSERT ON container_governance.approved_packages TO bdai_app_runtime;
GRANT INSERT ON container_governance.container_evidence TO bdai_app_runtime;

GRANT EXECUTE ON FUNCTION container_governance.is_image_deployable(UUID) TO bdai_readonly, bdai_app_runtime, bdai_auditor;
GRANT EXECUTE ON FUNCTION container_governance.is_release_certified(UUID) TO bdai_readonly, bdai_app_runtime, bdai_auditor;

REVOKE INSERT, UPDATE, DELETE ON governance_admin.schema_migrations FROM bdai_app_runtime;
REVOKE INSERT, UPDATE, DELETE ON governance_admin.schema_architecture_map FROM bdai_app_runtime;
REVOKE INSERT, UPDATE, DELETE ON governance_admin.schema_reference_rules FROM bdai_app_runtime;

GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA governance_admin TO bdai_break_glass;
