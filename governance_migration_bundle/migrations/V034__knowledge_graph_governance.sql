-- ============================================================================
-- BioDiscoveryAI Knowledge Graph Governance
-- Migration: V036__knowledge_graph_governance.sql
-- Purpose:
--   Govern knowledge graph entities, relationships, ontologies, graph versions,
--   graph validation, relationship provenance, impact analysis, and graph reviews.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS container_governance;

CREATE TABLE IF NOT EXISTS container_governance.ontologies (
    ontology_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ontology_name TEXT NOT NULL,
    ontology_version TEXT NOT NULL,
    ontology_description TEXT NOT NULL,
    source_uri TEXT,
    source_sha256 TEXT,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending','approved','rejected','retired')),
    approved_by TEXT,
    approved_at TIMESTAMPTZ,
    UNIQUE(ontology_name, ontology_version)
);

CREATE TABLE IF NOT EXISTS container_governance.knowledge_graphs (
    graph_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_name TEXT NOT NULL,
    graph_version TEXT NOT NULL,
    graph_description TEXT NOT NULL,
    domain_scope TEXT NOT NULL,
    owner TEXT NOT NULL,
    approval_status TEXT NOT NULL DEFAULT 'draft'
        CHECK (approval_status IN ('draft','approved','rejected','retired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(graph_name, graph_version)
);

CREATE TABLE IF NOT EXISTS container_governance.graph_entities (
    graph_entity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id UUID NOT NULL REFERENCES container_governance.knowledge_graphs(graph_id),
    entity_type TEXT NOT NULL,
    entity_key TEXT NOT NULL,
    entity_label TEXT NOT NULL,
    source_entity_type TEXT,
    source_entity_id TEXT,
    properties JSONB NOT NULL DEFAULT '{}',
    confidence_score NUMERIC(4,3) CHECK (confidence_score BETWEEN 0 AND 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(graph_id, entity_type, entity_key)
);

CREATE TABLE IF NOT EXISTS container_governance.graph_relationships (
    graph_relationship_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id UUID NOT NULL REFERENCES container_governance.knowledge_graphs(graph_id),
    subject_entity_id UUID NOT NULL REFERENCES container_governance.graph_entities(graph_entity_id),
    predicate TEXT NOT NULL,
    object_entity_id UUID NOT NULL REFERENCES container_governance.graph_entities(graph_entity_id),
    relationship_source TEXT NOT NULL,
    provenance_entity_type TEXT,
    provenance_entity_id TEXT,
    confidence_score NUMERIC(4,3) CHECK (confidence_score BETWEEN 0 AND 1),
    properties JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(graph_id, subject_entity_id, predicate, object_entity_id)
);

CREATE TABLE IF NOT EXISTS container_governance.graph_versions (
    graph_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id UUID NOT NULL REFERENCES container_governance.knowledge_graphs(graph_id),
    version_label TEXT NOT NULL,
    entity_count INT NOT NULL DEFAULT 0,
    relationship_count INT NOT NULL DEFAULT 0,
    export_uri TEXT,
    export_sha256 TEXT,
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(graph_id, version_label)
);

CREATE TABLE IF NOT EXISTS container_governance.graph_validations (
    graph_validation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id UUID NOT NULL REFERENCES container_governance.knowledge_graphs(graph_id),
    validation_type TEXT NOT NULL CHECK (validation_type IN ('schema','ontology','consistency','lineage','quality','manual_review')),
    validation_status TEXT NOT NULL CHECK (validation_status IN ('pass','fail','warning')),
    validation_summary TEXT NOT NULL,
    executed_by TEXT NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    evidence_uri TEXT,
    evidence_sha256 TEXT
);

CREATE OR REPLACE VIEW container_governance.v_graph_impact_analysis AS
SELECT
    kg.graph_name,
    kg.graph_version,
    ge.entity_type,
    ge.entity_key,
    ge.entity_label,
    COUNT(gr_out.graph_relationship_id) AS outgoing_relationships,
    COUNT(gr_in.graph_relationship_id) AS incoming_relationships
FROM container_governance.knowledge_graphs kg
JOIN container_governance.graph_entities ge ON ge.graph_id = kg.graph_id
LEFT JOIN container_governance.graph_relationships gr_out ON gr_out.subject_entity_id = ge.graph_entity_id
LEFT JOIN container_governance.graph_relationships gr_in ON gr_in.object_entity_id = ge.graph_entity_id
GROUP BY kg.graph_name, kg.graph_version, ge.entity_type, ge.entity_key, ge.entity_label;

CREATE INDEX IF NOT EXISTS idx_graph_entities_graph ON container_governance.graph_entities(graph_id);
CREATE INDEX IF NOT EXISTS idx_graph_entities_source ON container_governance.graph_entities(source_entity_type, source_entity_id);
CREATE INDEX IF NOT EXISTS idx_graph_relationships_subject ON container_governance.graph_relationships(subject_entity_id);
CREATE INDEX IF NOT EXISTS idx_graph_relationships_object ON container_governance.graph_relationships(object_entity_id);

COMMIT;
