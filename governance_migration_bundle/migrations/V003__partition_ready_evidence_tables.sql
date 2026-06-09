-- High-growth tables are partition-ready. 
-- Partitioning can be activated using postgres/migrations/010_enable_monthly_partitions.sql.
-- Every high-growth table includes:
--   run_id
--   created_at
--   metadata JSONB
--   indexes on created_at/run_id

CREATE TABLE IF NOT EXISTS evidence.execution_runs (
    run_id TEXT PRIMARY KEY,
    script_id TEXT NOT NULL REFERENCES registry.scripts(script_id),
    module_id TEXT NOT NULL REFERENCES registry.modules(module_id),
    target TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    actor TEXT,
    git_commit TEXT,
    git_branch TEXT,
    container_image TEXT,
    container_digest TEXT,
    nextflow_run_id TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS evidence.audit_events (
    audit_event_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    status TEXT NOT NULL,
    message TEXT,
    actor TEXT,
    previous_hash TEXT,
    event_hash TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (audit_event_id)
);

CREATE TABLE IF NOT EXISTS evidence.execution_steps (
    step_event_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    step_id TEXT NOT NULL,
    step_title TEXT NOT NULL,
    step_purpose TEXT,
    status TEXT NOT NULL,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (step_event_id)
);

CREATE TABLE IF NOT EXISTS evidence.error_events (
    error_event_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    error_code TEXT,
    error_message TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'High',
    stack_trace TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (error_event_id)
);

CREATE TABLE IF NOT EXISTS evidence.dependency_inventory (
    dependency_record_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    dependencies JSONB NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (dependency_record_id)
);

CREATE TABLE IF NOT EXISTS evidence.provenance_records (
    provenance_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    provenance JSONB NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provenance_id)
);

CREATE TABLE IF NOT EXISTS evidence.compliance_evidence (
    compliance_evidence_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    framework TEXT,
    control_id TEXT,
    evidence JSONB NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (compliance_evidence_id)
);

CREATE TABLE IF NOT EXISTS evidence.validation_results (
    validation_result_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    validation_type TEXT NOT NULL,
    requirement_id TEXT,
    test_id TEXT,
    status TEXT NOT NULL,
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (validation_result_id)
);

CREATE TABLE IF NOT EXISTS evidence.capa_deviation_records (
    capa_id TEXT PRIMARY KEY,
    run_id TEXT REFERENCES evidence.execution_runs(run_id) ON DELETE SET NULL,
    deviation_id TEXT,
    severity TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Open',
    description TEXT NOT NULL,
    root_cause TEXT,
    corrective_action TEXT,
    preventive_action TEXT,
    owner_ref TEXT,
    due_date DATE,
    closure_evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS evidence.resource_cost_metrics (
    metric_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    duration_seconds INTEGER,
    cpu_requested TEXT,
    memory_requested TEXT,
    storage_bytes BIGINT,
    cloud_provider TEXT,
    cost_center TEXT,
    estimated_cost NUMERIC(18, 6),
    metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (metric_id)
);
