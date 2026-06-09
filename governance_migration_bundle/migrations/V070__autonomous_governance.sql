-- ============================================================================
-- BioDiscoveryAI Autonomous Governance
-- Migration: V076__autonomous_governance.sql
-- Purpose:
--   Govern autonomous governance agents that detect risks, open CAPAs,
--   escalate issues, request revalidation, block releases, and recommend
--   actions under controlled permissions and human oversight.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_os;

CREATE TABLE IF NOT EXISTS governance_os.autonomous_governance_agents (
    governance_agent_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_code TEXT NOT NULL UNIQUE,
    agent_name TEXT NOT NULL,
    agent_description TEXT NOT NULL,
    agent_type TEXT NOT NULL CHECK (
        agent_type IN ('monitor','reviewer','recommender','orchestrator','sentinel','auditor','other')
    ),
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high','critical')),
    human_oversight_required BOOLEAN NOT NULL DEFAULT true,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.agent_permissions (
    agent_permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_agent_id UUID NOT NULL REFERENCES governance_os.autonomous_governance_agents(governance_agent_id),
    permission_code TEXT NOT NULL,
    permission_description TEXT NOT NULL,
    allowed_action TEXT NOT NULL,
    requires_human_approval BOOLEAN NOT NULL DEFAULT true,
    max_autonomy_level TEXT NOT NULL DEFAULT 'recommend'
        CHECK (max_autonomy_level IN ('observe','recommend','draft','execute_with_approval','execute_autonomously')),
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(governance_agent_id, permission_code)
);

CREATE TABLE IF NOT EXISTS governance_os.agent_runs (
    agent_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_agent_id UUID NOT NULL REFERENCES governance_os.autonomous_governance_agents(governance_agent_id),
    run_trigger TEXT NOT NULL,
    run_context JSONB NOT NULL DEFAULT '{}',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    run_status TEXT NOT NULL DEFAULT 'started'
        CHECK (run_status IN ('started','completed','failed','cancelled','blocked')),
    output_summary TEXT,
    output_payload JSONB NOT NULL DEFAULT '{}',
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_os.agent_actions (
    agent_action_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_run_id UUID NOT NULL REFERENCES governance_os.agent_runs(agent_run_id),
    governance_command_id UUID REFERENCES governance_os.governance_commands(governance_command_id),
    action_requested TEXT NOT NULL,
    action_rationale TEXT NOT NULL,
    autonomy_level TEXT NOT NULL CHECK (
        autonomy_level IN ('observe','recommend','draft','execute_with_approval','execute_autonomously')
    ),
    human_approval_status TEXT NOT NULL DEFAULT 'not_required'
        CHECK (human_approval_status IN ('not_required','pending','approved','rejected')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    action_status TEXT NOT NULL DEFAULT 'proposed'
        CHECK (action_status IN ('proposed','approved','executed','rejected','failed','cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_os.agent_safety_boundaries (
    agent_safety_boundary_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    governance_agent_id UUID NOT NULL REFERENCES governance_os.autonomous_governance_agents(governance_agent_id),
    boundary_name TEXT NOT NULL,
    boundary_description TEXT NOT NULL,
    prohibited_action TEXT NOT NULL,
    enforcement_mode TEXT NOT NULL DEFAULT 'block'
        CHECK (enforcement_mode IN ('block','warn','monitor')),
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(governance_agent_id, boundary_name)
);

CREATE OR REPLACE VIEW governance_os.v_autonomous_governance_status AS
SELECT
    aga.agent_code,
    aga.agent_name,
    aga.agent_type,
    aga.risk_level,
    aga.approval_status,
    COUNT(ar.agent_run_id) AS total_runs,
    COUNT(ar.agent_run_id) FILTER (WHERE ar.run_status = 'failed') AS failed_runs,
    COUNT(aa.agent_action_id) FILTER (WHERE aa.human_approval_status = 'pending') AS pending_human_approvals
FROM governance_os.autonomous_governance_agents aga
LEFT JOIN governance_os.agent_runs ar ON ar.governance_agent_id = aga.governance_agent_id
LEFT JOIN governance_os.agent_actions aa ON aa.agent_run_id = ar.agent_run_id
GROUP BY aga.agent_code, aga.agent_name, aga.agent_type, aga.risk_level, aga.approval_status;

CREATE INDEX IF NOT EXISTS idx_agent_runs_agent ON governance_os.agent_runs(governance_agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_actions_run ON governance_os.agent_actions(agent_run_id);

COMMIT;
