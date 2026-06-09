-- ============================================================================
-- BioDiscoveryAI Controlled Vocabularies, Data Quality, and Run Lifecycle
-- Migration: V092__controlled_vocabularies_constraints_and_run_lifecycle.sql
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS registry.run_statuses (
    status_code TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    terminal BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS registry.run_targets (
    target_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.run_states (
    run_state_code TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    terminal BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS registry.environment_types (
    environment_type_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.scheduler_types (
    scheduler_type_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.container_runtimes (
    container_runtime_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.storage_backends (
    storage_backend_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.criticality_levels (
    criticality_code TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    rank_order INT NOT NULL CHECK (rank_order > 0)
);

CREATE TABLE IF NOT EXISTS registry.retention_periods (
    retention_period_code TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    minimum_months INT CHECK (minimum_months IS NULL OR minimum_months > 0)
);

CREATE TABLE IF NOT EXISTS registry.signature_types (
    signature_type_code TEXT PRIMARY KEY,
    description TEXT NOT NULL
);

INSERT INTO registry.run_statuses(status_code, description, terminal) VALUES
('STARTED','Run has started.',false),
('RUNNING','Run is actively executing.',false),
('PASS','Run completed successfully.',true),
('FAIL','Run completed unsuccessfully.',true),
('ERROR','Run stopped because of an error.',true),
('CANCELLED','Run was cancelled before completion.',true),
('DRY_RUN','Run validated planned actions without production evidence finalization.',true)
ON CONFLICT (status_code) DO NOTHING;

INSERT INTO registry.run_targets(target_code, description) VALUES
('local','Local workstation or controlled local validation target.'),
('hpc','High-performance computing target.'),
('aws','Amazon Web Services target.'),
('azure','Microsoft Azure target.'),
('gcp','Google Cloud Platform target.'),
('hybrid','Hybrid execution target.'),
('other','Other controlled execution target.')
ON CONFLICT (target_code) DO NOTHING;

INSERT INTO registry.run_states(run_state_code, description, terminal) VALUES
('active','Run is open and mutable for normal execution updates.',false),
('finalized','Run is finalized and requires controlled correction for changes.',true),
('superseded','Run has been replaced by a later governed run.',true),
('corrected','Run has a controlled post-finalization correction record.',true),
('voided','Run is administratively voided but retained for auditability.',true)
ON CONFLICT (run_state_code) DO NOTHING;

INSERT INTO registry.environment_types(environment_type_code, description) VALUES
('local','Local development or validation environment.'),
('hpc','High-performance computing environment.'),
('aws','AWS cloud environment.'),
('azure','Azure cloud environment.'),
('gcp','GCP cloud environment.'),
('hybrid','Hybrid environment.'),
('other','Other governed environment.')
ON CONFLICT (environment_type_code) DO NOTHING;

INSERT INTO registry.scheduler_types(scheduler_type_code, description) VALUES
('none','No external scheduler.'),
('SLURM','SLURM scheduler.'),
('AWS Batch','AWS Batch scheduler.'),
('ECS','AWS ECS/Fargate service scheduler.'),
('Kubernetes','Kubernetes scheduler.'),
('Nextflow','Nextflow workflow scheduler.'),
('other','Other scheduler.')
ON CONFLICT (scheduler_type_code) DO NOTHING;

INSERT INTO registry.container_runtimes(container_runtime_code, description) VALUES
('none','No container runtime.'),
('docker','Docker runtime.'),
('apptainer','Apptainer runtime.'),
('singularity','Singularity runtime.'),
('containerd','containerd runtime.'),
('podman','Podman runtime.'),
('other','Other runtime.')
ON CONFLICT (container_runtime_code) DO NOTHING;

INSERT INTO registry.storage_backends(storage_backend_code, description) VALUES
('local-filesystem','Local filesystem storage.'),
('shared-filesystem','Shared filesystem storage.'),
('s3-object-lock','S3 Object Lock storage.'),
('s3','S3 storage.'),
('local-demo','Local demo artifact storage.'),
('database','Database-backed storage.'),
('other','Other governed storage backend.')
ON CONFLICT (storage_backend_code) DO NOTHING;

INSERT INTO registry.criticality_levels(criticality_code, description, rank_order) VALUES
('Low','Low criticality.',1),
('Medium','Medium criticality.',2),
('High','High criticality.',3),
('Critical','Critical regulated evidence.',4)
ON CONFLICT (criticality_code) DO NOTHING;

INSERT INTO registry.retention_periods(retention_period_code, description, minimum_months) VALUES
('none','No retention requirement beyond operational policy.',NULL),
('1_year','Retain for at least one year.',12),
('3_years','Retain for at least three years.',36),
('7_years','Retain for at least seven years.',84),
('10_years','Retain for at least ten years.',120),
('permanent','Retain permanently unless legal/compliance process permits disposition.',NULL)
ON CONFLICT (retention_period_code) DO NOTHING;

INSERT INTO registry.signature_types(signature_type_code, description) VALUES
('detached_json_signature','Detached JSON signature.'),
('pgp','PGP signature.'),
('x509','X.509 certificate-backed signature.'),
('kms','Cloud KMS-backed signature.'),
('cosign','Sigstore/cosign signature.'),
('manual_attestation','Manual electronic attestation.')
ON CONFLICT (signature_type_code) DO NOTHING;

ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS run_state TEXT NOT NULL DEFAULT 'active';
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS finalized_at TIMESTAMPTZ;
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS finalized_by TEXT;
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS superseded_by_run_id TEXT;
ALTER TABLE evidence.execution_runs ADD COLUMN IF NOT EXISTS correction_reason TEXT;

ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS fk_execution_runs_status_vocab;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT fk_execution_runs_status_vocab FOREIGN KEY (status) REFERENCES registry.run_statuses(status_code) NOT VALID;
ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS fk_execution_runs_target_vocab;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT fk_execution_runs_target_vocab FOREIGN KEY (target) REFERENCES registry.run_targets(target_code) NOT VALID;
ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS fk_execution_runs_run_state_vocab;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT fk_execution_runs_run_state_vocab FOREIGN KEY (run_state) REFERENCES registry.run_states(run_state_code) NOT VALID;
ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS fk_execution_runs_superseded_by;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT fk_execution_runs_superseded_by FOREIGN KEY (superseded_by_run_id) REFERENCES evidence.execution_runs(run_id) NOT VALID;

ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS fk_execution_environments_type_vocab;
ALTER TABLE registry.execution_environments ADD CONSTRAINT fk_execution_environments_type_vocab FOREIGN KEY (environment_type) REFERENCES registry.environment_types(environment_type_code) NOT VALID;
ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS fk_execution_environments_scheduler_vocab;
ALTER TABLE registry.execution_environments ADD CONSTRAINT fk_execution_environments_scheduler_vocab FOREIGN KEY (scheduler_type) REFERENCES registry.scheduler_types(scheduler_type_code) NOT VALID;
ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS fk_execution_environments_runtime_vocab;
ALTER TABLE registry.execution_environments ADD CONSTRAINT fk_execution_environments_runtime_vocab FOREIGN KEY (container_runtime) REFERENCES registry.container_runtimes(container_runtime_code) NOT VALID;
ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS fk_execution_environments_storage_vocab;
ALTER TABLE registry.execution_environments ADD CONSTRAINT fk_execution_environments_storage_vocab FOREIGN KEY (storage_class) REFERENCES registry.storage_backends(storage_backend_code) NOT VALID;

ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS fk_artifacts_artifact_type_registry;
ALTER TABLE archive.artifacts ADD CONSTRAINT fk_artifacts_artifact_type_registry FOREIGN KEY (artifact_type) REFERENCES registry.artifact_types(artifact_type_id) NOT VALID;
ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS fk_artifacts_storage_backend_vocab;
ALTER TABLE archive.artifacts ADD CONSTRAINT fk_artifacts_storage_backend_vocab FOREIGN KEY (storage_backend) REFERENCES registry.storage_backends(storage_backend_code) NOT VALID;
ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS fk_artifacts_criticality_vocab;
ALTER TABLE archive.artifacts ADD CONSTRAINT fk_artifacts_criticality_vocab FOREIGN KEY (criticality) REFERENCES registry.criticality_levels(criticality_code) NOT VALID;
ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS fk_artifacts_retention_period_vocab;
ALTER TABLE archive.artifacts ADD CONSTRAINT fk_artifacts_retention_period_vocab FOREIGN KEY (retention_period) REFERENCES registry.retention_periods(retention_period_code) NOT VALID;

ALTER TABLE signing.evidence_snapshots DROP CONSTRAINT IF EXISTS fk_evidence_snapshots_signature_type_vocab;
ALTER TABLE signing.evidence_snapshots ADD CONSTRAINT fk_evidence_snapshots_signature_type_vocab FOREIGN KEY (signature_type) REFERENCES registry.signature_types(signature_type_code) NOT VALID;

ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS chk_execution_runs_time_quality;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT chk_execution_runs_time_quality CHECK (ended_at IS NULL OR ended_at >= started_at) NOT VALID;
ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS chk_execution_runs_duration_nonnegative;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT chk_execution_runs_duration_nonnegative CHECK (duration_seconds IS NULL OR duration_seconds >= 0) NOT VALID;
ALTER TABLE evidence.execution_runs DROP CONSTRAINT IF EXISTS chk_execution_runs_finalized_fields;
ALTER TABLE evidence.execution_runs ADD CONSTRAINT chk_execution_runs_finalized_fields CHECK (run_state <> 'finalized' OR finalized_at IS NOT NULL) NOT VALID;

ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS chk_execution_environments_cpu_positive;
ALTER TABLE registry.execution_environments ADD CONSTRAINT chk_execution_environments_cpu_positive CHECK (cpu_count IS NULL OR cpu_count > 0) NOT VALID;
ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS chk_execution_environments_memory_positive;
ALTER TABLE registry.execution_environments ADD CONSTRAINT chk_execution_environments_memory_positive CHECK (memory_gb IS NULL OR memory_gb > 0) NOT VALID;
ALTER TABLE registry.execution_environments DROP CONSTRAINT IF EXISTS chk_execution_environments_gpu_nonnegative;
ALTER TABLE registry.execution_environments ADD CONSTRAINT chk_execution_environments_gpu_nonnegative CHECK (gpu_count IS NULL OR gpu_count >= 0) NOT VALID;

ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS chk_artifacts_size_nonnegative;
ALTER TABLE archive.artifacts ADD CONSTRAINT chk_artifacts_size_nonnegative CHECK (size_bytes IS NULL OR size_bytes >= 0) NOT VALID;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (92, '092', 'Controlled vocabularies, constraints, and run lifecycle', 'V092__controlled_vocabularies_constraints_and_run_lifecycle.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
