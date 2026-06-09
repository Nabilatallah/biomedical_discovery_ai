-- ============================================================================
-- BioDiscoveryAI Enterprise Governance Operating System
-- Migration: V075__enterprise_governance_os.sql
-- Purpose:
--   Establish the universal governance OS kernel: commands, tasks, actions,
--   jobs, schedulers, state machines, execution logs, and action lineage.
--   This extends the governance kernel beyond entities/events/workflows into
--   executable governance operations.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_os;

CREATE TABLE IF NOT EXISTS governance_os.command_types (
    command_type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    command_code TEXT NOT NULL UNIQUE,
    command_name TEXT NOT NULL,
    command_description TEXT NOT NULL,
    owning_domain TEXT NOT NULL,
    requires_approval BOOLEAN NOT NULL DEFAULT true,
    regulated_command BOOLEAN NOT NULL DEFAULT true,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.governance_commands (
    governance_command_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    command_type_id UUID NOT NULL REFERENCES governance_os.command_types(command_type_id),
    command_name TEXT NOT NULL,
    command_description TEXT NOT NULL,
    requested_by TEXT NOT NULL DEFAULT current_user,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    target_entity_id UUID,
    target_enterprise_object_id TEXT,
    command_payload JSONB NOT NULL DEFAULT '{}',
    command_status TEXT NOT NULL DEFAULT 'requested'
        CHECK (command_status IN ('requested','approved','rejected','queued','running','completed','failed','cancelled')),
    approval_required BOOLEAN NOT NULL DEFAULT true,
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.governance_tasks (
    governance_task_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_command_id UUID REFERENCES governance_os.governance_commands(governance_command_id),
    task_name TEXT NOT NULL,
    task_description TEXT NOT NULL,
    assigned_to TEXT,
    task_status TEXT NOT NULL DEFAULT 'open'
        CHECK (task_status IN ('open','assigned','in_progress','blocked','completed','failed','cancelled')),
    priority TEXT NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('low','medium','high','critical')),
    due_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.governance_actions (
    governance_action_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_task_id UUID REFERENCES governance_os.governance_tasks(governance_task_id),
    action_type TEXT NOT NULL CHECK (
        action_type IN ('create','update','approve','reject','execute','notify','escalate','block','unblock','retire','archive','verify')
    ),
    action_summary TEXT NOT NULL,
    action_payload JSONB NOT NULL DEFAULT '{}',
    action_status TEXT NOT NULL DEFAULT 'planned'
        CHECK (action_status IN ('planned','running','completed','failed','cancelled')),
    executed_by TEXT,
    executed_at TIMESTAMPTZ,
    result_summary TEXT,
    result_payload JSONB NOT NULL DEFAULT '{}',
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.governance_jobs (
    governance_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_name TEXT NOT NULL,
    job_description TEXT NOT NULL,
    job_type TEXT NOT NULL CHECK (
        job_type IN ('scheduled','event_driven','manual','condition_watch','batch','real_time')
    ),
    schedule_expression TEXT,
    trigger_condition TEXT,
    job_status TEXT NOT NULL DEFAULT 'enabled'
        CHECK (job_status IN ('enabled','disabled','paused','retired')),
    owner TEXT NOT NULL,
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.governance_job_runs (
    governance_job_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_job_id UUID NOT NULL REFERENCES governance_os.governance_jobs(governance_job_id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    run_status TEXT NOT NULL DEFAULT 'started'
        CHECK (run_status IN ('started','passed','failed','warning','cancelled')),
    run_summary TEXT,
    output_payload JSONB NOT NULL DEFAULT '{}',
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE OR REPLACE VIEW governance_os.v_governance_os_activity AS
SELECT
    gc.governance_command_id,
    ct.command_code,
    gc.command_name,
    gc.command_status,
    COUNT(gt.governance_task_id) AS task_count,
    COUNT(gt.governance_task_id) FILTER (WHERE gt.task_status = 'completed') AS completed_tasks,
    COUNT(ga.governance_action_id) AS action_count
FROM governance_os.governance_commands gc
JOIN governance_os.command_types ct ON ct.command_type_id = gc.command_type_id
LEFT JOIN governance_os.governance_tasks gt ON gt.governance_command_id = gc.governance_command_id
LEFT JOIN governance_os.governance_actions ga ON ga.governance_task_id = gt.governance_task_id
GROUP BY gc.governance_command_id, ct.command_code, gc.command_name, gc.command_status;

INSERT INTO governance_os.command_types (
    command_code, command_name, command_description, owning_domain, requires_approval, regulated_command
)
VALUES
('OPEN_CAPA','Open CAPA','Open a corrective/preventive action for a governed issue.','quality',true,true),
('BLOCK_RELEASE','Block Release','Block a release based on policy, risk, incident, validation, or compliance condition.','release_governance',true,true),
('REQUEST_REVALIDATION','Request Revalidation','Request periodic or event-triggered revalidation.','compliance',true,true),
('ESCALATE_RISK','Escalate Risk','Escalate risk to governance leadership.','risk_management',true,true),
('RETIRE_ENTITY','Retire Entity','Retire governed object from active use.','enterprise_governance',true,true)
ON CONFLICT (command_code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_governance_commands_status ON governance_os.governance_commands(command_status);
CREATE INDEX IF NOT EXISTS idx_governance_tasks_status ON governance_os.governance_tasks(task_status);
CREATE INDEX IF NOT EXISTS idx_governance_actions_status ON governance_os.governance_actions(action_status);
CREATE INDEX IF NOT EXISTS idx_governance_jobs_status ON governance_os.governance_jobs(job_status);

COMMIT;
