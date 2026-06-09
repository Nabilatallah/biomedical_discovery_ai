CREATE TABLE IF NOT EXISTS archive.artifacts (
    artifact_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT REFERENCES evidence.execution_runs(run_id) ON DELETE SET NULL,
    artifact_name TEXT NOT NULL,
    artifact_type TEXT NOT NULL,
    storage_backend TEXT NOT NULL,
    storage_uri TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    size_bytes BIGINT,
    content_type TEXT,
    criticality TEXT NOT NULL DEFAULT 'High',
    retention_period TEXT NOT NULL DEFAULT '7_years',
    legal_hold BOOLEAN NOT NULL DEFAULT false,
    immutable BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (artifact_id),
    CONSTRAINT chk_artifact_sha256 CHECK (sha256 ~ '^[a-fA-F0-9]{64}$')
);

CREATE TABLE IF NOT EXISTS reporting.execution_reports (
    report_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES evidence.execution_runs(run_id) ON DELETE CASCADE,
    report_type TEXT NOT NULL,
    report_markdown TEXT,
    report_uri TEXT,
    report_hash TEXT,
    rendered_format TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (report_id)
);

CREATE TABLE IF NOT EXISTS signing.evidence_snapshots (
    snapshot_id UUID DEFAULT gen_random_uuid(),
    run_id TEXT REFERENCES evidence.execution_runs(run_id) ON DELETE SET NULL,
    release_id TEXT,
    snapshot_uri TEXT,
    snapshot_hash TEXT NOT NULL,
    signature_uri TEXT,
    signature_type TEXT,
    signed_by TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (snapshot_id)
);

CREATE TABLE IF NOT EXISTS api_contract.evidence_api_contracts (
    contract_id TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    contract_json JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
