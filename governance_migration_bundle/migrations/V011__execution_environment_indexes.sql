-- =============================================================================
-- 011 Indexes for execution environment lineage
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_execution_environments_type
    ON registry.execution_environments(environment_type);
CREATE INDEX IF NOT EXISTS idx_execution_environments_scheduler
    ON registry.execution_environments(scheduler_type);
CREATE INDEX IF NOT EXISTS idx_execution_environments_container_runtime
    ON registry.execution_environments(container_runtime);
CREATE INDEX IF NOT EXISTS idx_execution_environments_gpu_type
    ON registry.execution_environments(gpu_type);
CREATE INDEX IF NOT EXISTS idx_runs_environment_id
    ON evidence.execution_runs(environment_id);
CREATE INDEX IF NOT EXISTS idx_runs_scheduler_job_id
    ON evidence.execution_runs(scheduler_job_id);
CREATE INDEX IF NOT EXISTS idx_runs_execution_backend
    ON evidence.execution_runs(execution_backend);
CREATE INDEX IF NOT EXISTS idx_runs_storage_backend
    ON evidence.execution_runs(storage_backend);
