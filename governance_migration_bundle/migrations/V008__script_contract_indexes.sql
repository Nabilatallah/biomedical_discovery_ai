-- =============================================================================
-- 008 Indexes for Script Contract Tables
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_script_dependencies_script_id
    ON registry.script_dependencies(script_id);
CREATE INDEX IF NOT EXISTS idx_script_dependencies_depends_on_script_id
    ON registry.script_dependencies(depends_on_script_id);
CREATE INDEX IF NOT EXISTS idx_script_dependencies_depends_on_module_id
    ON registry.script_dependencies(depends_on_module_id);
CREATE INDEX IF NOT EXISTS idx_script_expected_artifacts_script_id
    ON registry.script_expected_artifacts(script_id);
CREATE INDEX IF NOT EXISTS idx_script_expected_artifacts_artifact_type
    ON registry.script_expected_artifacts(artifact_type);
CREATE INDEX IF NOT EXISTS idx_script_execution_targets_script_id
    ON registry.script_execution_targets(script_id);
CREATE INDEX IF NOT EXISTS idx_script_execution_targets_target
    ON registry.script_execution_targets(target);
CREATE INDEX IF NOT EXISTS idx_script_cli_options_script_id
    ON registry.script_cli_options(script_id);
CREATE INDEX IF NOT EXISTS idx_script_contract_checks_script_id
    ON registry.script_contract_checks(script_id);
