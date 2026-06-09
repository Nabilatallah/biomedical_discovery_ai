-- V050__decision_governance.sql
-- BioDiscoveryAI Governance Expansion
-- Purpose: Decision models, decision logs, accountability, approvals, decision lineage.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- Enterprise-grade governance domain scaffold.
-- Expand into full implementation consistent with V011-V048.

COMMIT;
