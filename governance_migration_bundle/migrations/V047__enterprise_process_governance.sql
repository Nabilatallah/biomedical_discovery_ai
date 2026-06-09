-- V049__enterprise_process_governance.sql
-- BioDiscoveryAI Governance Expansion
-- Purpose: BPMN, process catalog, process owners, controls, process lifecycle governance.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- Enterprise-grade governance domain scaffold.
-- Expand into full implementation consistent with V011-V048.

COMMIT;
