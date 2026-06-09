-- =============================================================================
-- 007 Script Dependency, Execution, CLI, and Expected Artifact Contracts
-- =============================================================================
-- Purpose:
--   Make script lineage, planned dependencies, supported execution targets,
--   CLI option semantics, and expected artifact outputs first-class database
--   contracts instead of informal documentation or runtime-only JSONB.
-- =============================================================================

CREATE TABLE IF NOT EXISTS registry.script_dependencies (
    dependency_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    script_id TEXT NOT NULL REFERENCES registry.scripts(script_id) ON DELETE CASCADE,
    depends_on_script_id TEXT REFERENCES registry.scripts(script_id),
    depends_on_module_id TEXT REFERENCES registry.modules(module_id),
    dependency_type TEXT NOT NULL,
    required BOOLEAN NOT NULL DEFAULT true,
    version_constraint TEXT,
    purpose TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT script_dependency_has_target CHECK (
        depends_on_script_id IS NOT NULL OR depends_on_module_id IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS registry.script_expected_artifacts (
    expected_artifact_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    script_id TEXT NOT NULL REFERENCES registry.scripts(script_id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL REFERENCES registry.artifact_types(artifact_type_id),
    artifact_name_pattern TEXT,
    required BOOLEAN NOT NULL DEFAULT true,
    retention_period TEXT NOT NULL DEFAULT '7_years',
    storage_backend TEXT NOT NULL DEFAULT 's3-object-lock',
    validation_rule JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (script_id, artifact_type, artifact_name_pattern)
);

CREATE TABLE IF NOT EXISTS registry.script_execution_targets (
    execution_target_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    script_id TEXT NOT NULL REFERENCES registry.scripts(script_id) ON DELETE CASCADE,
    target TEXT NOT NULL,
    runtime TEXT NOT NULL,
    command_template TEXT NOT NULL,
    scheduler TEXT,
    container_runtime TEXT,
    environment_requirements JSONB NOT NULL DEFAULT '{}'::jsonb,
    security_controls JSONB NOT NULL DEFAULT '{}'::jsonb,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (script_id, target, runtime)
);

CREATE TABLE IF NOT EXISTS registry.script_cli_options (
    cli_option_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    script_id TEXT NOT NULL REFERENCES registry.scripts(script_id) ON DELETE CASCADE,
    option_name TEXT NOT NULL,
    value_name TEXT,
    required BOOLEAN NOT NULL DEFAULT false,
    default_value TEXT,
    allowed_values TEXT[] NOT NULL DEFAULT '{}',
    description TEXT NOT NULL,
    example_value TEXT,
    applies_to_targets TEXT[] NOT NULL DEFAULT '{}',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (script_id, option_name)
);

CREATE TABLE IF NOT EXISTS registry.script_contract_checks (
    contract_check_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    script_id TEXT NOT NULL REFERENCES registry.scripts(script_id) ON DELETE CASCADE,
    check_name TEXT NOT NULL,
    check_type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'High',
    required BOOLEAN NOT NULL DEFAULT true,
    rule JSONB NOT NULL DEFAULT '{}'::jsonb,
    remediation TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (script_id, check_name)
);
