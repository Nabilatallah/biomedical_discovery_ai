-- ============================================================================
-- V039__enterprise_architecture_repository.sql
-- BioDiscoveryAI Enterprise Governance Expansion
-- Purpose:
--   Capability maps, business architecture, application portfolio, technology portfolio, reference architectures, ADRs, lifecycle management.
--
-- Status:
--   Enterprise-grade migration scaffold intended for expansion into full SQL
--   implementation consistent with V011-V038 governance architecture.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- Reserved governance domain:
-- Capability maps, business architecture, application portfolio, technology portfolio, reference architectures, ADRs, lifecycle management.

COMMIT;
