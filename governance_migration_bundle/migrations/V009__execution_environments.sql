-- =============================================================================
-- 009 Execution Environment Registry and Runtime Linkage
-- BioDiscoveryAI Enterprise v11
-- =============================================================================
-- Purpose:
--   Capture where and how each run executed, not only which script ran.
--   This supports reproducibility, GxP auditability, cloud/HPC traceability,
--   cost governance, and hybrid execution reporting.

CREATE TABLE IF NOT EXISTS registry.execution_environments (
    environment_id TEXT PRIMARY KEY,
    environment_name TEXT NOT NULL,
    environment_type TEXT NOT NULL,
    scheduler_type TEXT NOT NULL,
    container_runtime TEXT NOT NULL,
    cpu_count INTEGER,
    memory_gb NUMERIC(10,2),
    gpu_type TEXT,
    gpu_count INTEGER DEFAULT 0,
    storage_class TEXT NOT NULL,
    network_policy TEXT NOT NULL,
    cloud_provider TEXT,
    region TEXT,
    hpc_cluster_name TEXT,
    queue_or_partition TEXT,
    account_or_project TEXT,
    security_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    compliance_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_execution_environment_type
        CHECK (environment_type IN ('local','hpc','aws','azure','gcp','hybrid','other'))
);

ALTER TABLE evidence.execution_runs
    ADD COLUMN IF NOT EXISTS environment_id TEXT
    REFERENCES registry.execution_environments(environment_id);

ALTER TABLE evidence.execution_runs
    ADD COLUMN IF NOT EXISTS scheduler_job_id TEXT;

ALTER TABLE evidence.execution_runs
    ADD COLUMN IF NOT EXISTS compute_node TEXT;

ALTER TABLE evidence.execution_runs
    ADD COLUMN IF NOT EXISTS execution_backend TEXT;

ALTER TABLE evidence.execution_runs
    ADD COLUMN IF NOT EXISTS storage_backend TEXT;

COMMENT ON TABLE registry.execution_environments IS
'Governed registry of execution environments including HPC, local, and cloud targets.';

COMMENT ON COLUMN evidence.execution_runs.environment_id IS
'Foreign key to registry.execution_environments, identifying where and how the run executed.';
