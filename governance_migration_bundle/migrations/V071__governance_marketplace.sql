-- ============================================================================
-- BioDiscoveryAI Governance Marketplace
-- Migration: V077__governance_marketplace.sql
-- Purpose:
--   Register reusable governance assets: policy bundles, control libraries,
--   validation packs, risk libraries, workflow templates, evidence packet
--   templates, SOPs, and reusable compliance modules.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS governance_marketplace;

CREATE TABLE IF NOT EXISTS governance_marketplace.marketplace_assets (
    marketplace_asset_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_code TEXT NOT NULL UNIQUE,
    asset_name TEXT NOT NULL,
    asset_description TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (
        asset_type IN ('policy_bundle','control_library','validation_pack','risk_library','workflow_template','evidence_template','sop','training_pack','dashboard','connector','other')
    ),
    asset_version TEXT NOT NULL,
    owner TEXT NOT NULL,
    artifact_uri TEXT NOT NULL,
    artifact_sha256 TEXT NOT NULL,
    license_terms TEXT,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(asset_code, asset_version)
);

CREATE TABLE IF NOT EXISTS governance_marketplace.asset_dependencies (
    asset_dependency_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    marketplace_asset_id UUID NOT NULL REFERENCES governance_marketplace.marketplace_assets(marketplace_asset_id),
    depends_on_asset_id UUID NOT NULL REFERENCES governance_marketplace.marketplace_assets(marketplace_asset_id),
    dependency_reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(marketplace_asset_id, depends_on_asset_id)
);

CREATE TABLE IF NOT EXISTS governance_marketplace.asset_installations (
    asset_installation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    marketplace_asset_id UUID NOT NULL REFERENCES governance_marketplace.marketplace_assets(marketplace_asset_id),
    target_environment TEXT NOT NULL,
    installed_by TEXT NOT NULL,
    installed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    installation_status TEXT NOT NULL DEFAULT 'installed'
        CHECK (installation_status IN ('installed','failed','removed','superseded')),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE TABLE IF NOT EXISTS governance_marketplace.asset_reviews (
    asset_review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    marketplace_asset_id UUID NOT NULL REFERENCES governance_marketplace.marketplace_assets(marketplace_asset_id),
    reviewer_identity TEXT NOT NULL,
    review_type TEXT NOT NULL CHECK (review_type IN ('security','quality','compliance','architecture','legal')),
    review_decision TEXT NOT NULL CHECK (review_decision IN ('approved','rejected','needs_revision')),
    review_comments TEXT NOT NULL,
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE VIEW governance_marketplace.v_marketplace_asset_status AS
SELECT
    ma.asset_code,
    ma.asset_name,
    ma.asset_type,
    ma.asset_version,
    ma.approval_status,
    COUNT(ai.asset_installation_id) AS installation_count,
    COUNT(ar.asset_review_id) AS review_count
FROM governance_marketplace.marketplace_assets ma
LEFT JOIN governance_marketplace.asset_installations ai ON ai.marketplace_asset_id = ma.marketplace_asset_id
LEFT JOIN governance_marketplace.asset_reviews ar ON ar.marketplace_asset_id = ma.marketplace_asset_id
GROUP BY ma.asset_code, ma.asset_name, ma.asset_type, ma.asset_version, ma.approval_status;

COMMIT;
