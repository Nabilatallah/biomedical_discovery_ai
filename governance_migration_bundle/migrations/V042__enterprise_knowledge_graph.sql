-- ============================================================================
-- V044__enterprise_knowledge_graph.sql
-- BioDiscoveryAI Enterprise Governance Expansion
-- Purpose:
--   Cross-domain enterprise graph linking people, vendors, risks, studies, containers, images, data, models, twins, publications.
--
-- Status:
--   Enterprise-grade migration scaffold intended for expansion into full SQL
--   implementation consistent with V011-V038 governance architecture.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

-- Reserved governance domain:
-- Cross-domain enterprise graph linking people, vendors, risks, studies, containers, images, data, models, twins, publications.

COMMIT;
