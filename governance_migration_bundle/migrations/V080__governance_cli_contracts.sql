-- ============================================================================
-- BioDiscoveryAI Governance CLI Contracts
-- Migration: V086__governance_cli_contracts.sql
-- Purpose:
--   Define stable CLI command contracts for developers, builders, validators,
--   security reviewers, release managers, auditors, and automation pipelines.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_contracts;

CREATE TABLE IF NOT EXISTS governance_contracts.cli_tools (
    cli_tool_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tool_code TEXT NOT NULL UNIQUE,
    tool_name TEXT NOT NULL,
    tool_description TEXT NOT NULL,
    tool_owner TEXT NOT NULL,
    executable_name TEXT NOT NULL,
    current_version TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','deprecated','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.cli_commands (
    cli_command_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cli_tool_id UUID NOT NULL REFERENCES governance_contracts.cli_tools(cli_tool_id),
    command_name TEXT NOT NULL,
    command_description TEXT NOT NULL,
    command_group TEXT NOT NULL,
    command_version TEXT NOT NULL,
    input_schema JSONB NOT NULL DEFAULT '{}',
    output_schema JSONB NOT NULL DEFAULT '{}',
    required_role TEXT,
    audit_required BOOLEAN NOT NULL DEFAULT true,
    approval_required BOOLEAN NOT NULL DEFAULT false,
    active BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(cli_tool_id, command_name, command_version)
);

CREATE TABLE IF NOT EXISTS governance_contracts.cli_command_examples (
    cli_command_example_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cli_command_id UUID NOT NULL REFERENCES governance_contracts.cli_commands(cli_command_id),
    example_name TEXT NOT NULL,
    example_description TEXT NOT NULL,
    example_command TEXT NOT NULL,
    expected_result TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_contracts.cli_execution_logs (
    cli_execution_log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cli_command_id UUID REFERENCES governance_contracts.cli_commands(cli_command_id),
    executed_by TEXT NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    execution_environment TEXT,
    command_line TEXT NOT NULL,
    input_payload JSONB NOT NULL DEFAULT '{}',
    output_payload JSONB NOT NULL DEFAULT '{}',
    exit_code INT,
    execution_status TEXT NOT NULL CHECK (execution_status IN ('started','passed','failed','cancelled')),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_contracts.cli_contract_tests (
    cli_contract_test_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cli_command_id UUID NOT NULL REFERENCES governance_contracts.cli_commands(cli_command_id),
    test_name TEXT NOT NULL,
    test_description TEXT NOT NULL,
    expected_exit_code INT NOT NULL DEFAULT 0,
    expected_result TEXT NOT NULL,
    test_status TEXT NOT NULL DEFAULT 'not_run'
        CHECK (test_status IN ('not_run','pass','fail','blocked')),
    last_run_at TIMESTAMPTZ,
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE OR REPLACE VIEW governance_contracts.v_cli_contract_readiness AS
SELECT
    t.tool_code,
    t.tool_name,
    t.current_version,
    t.approval_status,
    COUNT(c.cli_command_id) AS command_count,
    COUNT(ct.cli_contract_test_id) FILTER (WHERE ct.test_status = 'pass') AS passed_tests,
    COUNT(ct.cli_contract_test_id) FILTER (WHERE ct.test_status = 'fail') AS failed_tests
FROM governance_contracts.cli_tools t
LEFT JOIN governance_contracts.cli_commands c ON c.cli_tool_id = t.cli_tool_id
LEFT JOIN governance_contracts.cli_contract_tests ct ON ct.cli_command_id = c.cli_command_id
GROUP BY t.tool_code, t.tool_name, t.current_version, t.approval_status;

INSERT INTO governance_contracts.cli_tools (
    tool_code, tool_name, tool_description, tool_owner, executable_name, current_version, approval_status, approved_by, approved_at
)
VALUES
('BDAI_GOV_CLI','BioDiscoveryAI Governance CLI','Primary CLI for governance registration, validation, evidence, release, and audit operations.','Platform Engineering','bdai-gov','1.0.0','approved','Architecture Review Board',now())
ON CONFLICT (tool_code) DO NOTHING;

COMMIT;
