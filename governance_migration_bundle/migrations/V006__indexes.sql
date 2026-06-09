CREATE INDEX IF NOT EXISTS idx_runs_script ON evidence.execution_runs(script_id);
CREATE INDEX IF NOT EXISTS idx_runs_module ON evidence.execution_runs(module_id);
CREATE INDEX IF NOT EXISTS idx_runs_status ON evidence.execution_runs(status);
CREATE INDEX IF NOT EXISTS idx_runs_created ON evidence.execution_runs(created_at);

CREATE INDEX IF NOT EXISTS idx_audit_run ON evidence.audit_events(run_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON evidence.audit_events(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_type ON evidence.audit_events(event_type);

CREATE INDEX IF NOT EXISTS idx_steps_run ON evidence.execution_steps(run_id);
CREATE INDEX IF NOT EXISTS idx_steps_created ON evidence.execution_steps(created_at);

CREATE INDEX IF NOT EXISTS idx_errors_run ON evidence.error_events(run_id);
CREATE INDEX IF NOT EXISTS idx_errors_created ON evidence.error_events(created_at);

CREATE INDEX IF NOT EXISTS idx_artifacts_run ON archive.artifacts(run_id);
CREATE INDEX IF NOT EXISTS idx_artifacts_created ON archive.artifacts(created_at);
CREATE INDEX IF NOT EXISTS idx_artifacts_type ON archive.artifacts(artifact_type);

CREATE INDEX IF NOT EXISTS idx_reports_run ON reporting.execution_reports(run_id);
CREATE INDEX IF NOT EXISTS idx_snapshots_run ON signing.evidence_snapshots(run_id);
