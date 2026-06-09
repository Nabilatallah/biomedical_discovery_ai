-- ============================================================================
-- BioDiscoveryAI Schema Architecture Map and Reference Rules
-- Migration: V108__schema_architecture_map_and_reference_rules.sql
-- Purpose:
--   Document schema ownership, responsibility boundaries, lifecycle status, and
--   allowed cross-schema reference rules so future additions stay additive and
--   do not blur domain boundaries.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS governance_admin.schema_architecture_map (
    schema_name TEXT PRIMARY KEY,
    domain_name TEXT NOT NULL,
    responsibility_summary TEXT NOT NULL,
    owning_role TEXT NOT NULL,
    system_layer TEXT NOT NULL CHECK (
        system_layer IN (
            'core_registry',
            'core_evidence',
            'artifact_archive',
            'reporting',
            'retention',
            'signing',
            'api_contract',
            'administration',
            'specialized_subsystem',
            'enterprise_governance',
            'platform_service',
            'marketplace',
            'external_integration'
        )
    ),
    regulated_criticality TEXT NOT NULL DEFAULT 'medium'
        CHECK (regulated_criticality IN ('low','medium','high','critical')),
    allowed_to_own_operational_data BOOLEAN NOT NULL DEFAULT true,
    allowed_to_own_reference_data BOOLEAN NOT NULL DEFAULT true,
    allowed_to_own_audit_data BOOLEAN NOT NULL DEFAULT false,
    allowed_to_own_security_controls BOOLEAN NOT NULL DEFAULT false,
    lifecycle_status TEXT NOT NULL DEFAULT 'active'
        CHECK (lifecycle_status IN ('planned','active','deprecated','retired','superseded')),
    boundary_notes TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS governance_admin.schema_reference_rules (
    reference_rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_schema TEXT NOT NULL,
    target_schema TEXT NOT NULL,
    reference_type TEXT NOT NULL CHECK (
        reference_type IN (
            'foreign_key',
            'read_only_view',
            'reporting_query',
            'admin_metadata',
            'event_reference',
            'contract_reference',
            'prohibited'
        )
    ),
    allowed BOOLEAN NOT NULL DEFAULT true,
    enforcement_level TEXT NOT NULL DEFAULT 'architectural'
        CHECK (enforcement_level IN ('architectural','review_required','database_enforced','prohibited')),
    rationale TEXT NOT NULL,
    review_required BOOLEAN NOT NULL DEFAULT false,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(source_schema, target_schema, reference_type)
);

INSERT INTO governance_admin.schema_architecture_map (
    schema_name, domain_name, responsibility_summary, owning_role, system_layer,
    regulated_criticality, allowed_to_own_operational_data, allowed_to_own_reference_data,
    allowed_to_own_audit_data, allowed_to_own_security_controls, boundary_notes
)
VALUES
('registry','Core Registry','Owns durable reference data: modules, scripts, actors, vocabularies, artifact types, controls, and execution environments.','Data Governance','core_registry','critical',false,true,false,false,'Registry is the source of truth for controlled terms and reference entities. It should not store high-growth runtime evidence.'),
('evidence','Execution Evidence','Owns run-scoped operational evidence: runs, audit events, steps, errors, validation results, approvals, signatures, corrections, and ingestion records.','Compliance Engineering','core_evidence','critical',true,false,true,false,'Evidence owns what happened. It may reference registry, archive, signing, retention, and governance_admin metadata but should not duplicate registry definitions.'),
('archive','Artifact Archive','Owns registered produced artifacts, storage URIs, hashes, artifact retention fields, and immutable artifact evidence.','Records Management','artifact_archive','critical',true,false,false,false,'Archive stores artifact metadata and integrity anchors. Large binary objects remain in governed external storage such as S3 Object Lock.'),
('reporting','Evidence Reporting','Owns generated report records and report metadata derived from registry/evidence/archive data.','Compliance Reporting','reporting','high',true,false,false,false,'Reporting should be derived or report-oriented. It should not become the system of record for execution facts.'),
('retention','Retention and Legal Hold','Owns retention policies, legal holds, disposition queues, and disposition records.','Records Management','retention','critical',true,true,true,false,'Retention controls record lifecycle. It may reference evidence approvals and registry actors.'),
('signing','Snapshot Signing','Owns signed evidence snapshots and signature metadata for evidence packages.','Quality Assurance','signing','critical',true,false,true,false,'Signing records package-level signatures. Detailed approval/e-signature workflow lives in evidence.'),
('api_contract','Evidence API Contracts','Owns API contract definitions and versions for evidence ingestion and retrieval.','Platform Engineering','api_contract','high',false,true,false,false,'API contract tables describe interfaces. Runtime API requests live in evidence.ingestion_* tables.'),
('audit','Audit Support','Reserved for audit-support extensions that are not run-scoped evidence events.','Compliance Engineering','administration','high',true,false,true,false,'Do not duplicate evidence.audit_events here; use only for future cross-system audit support if needed.'),
('governance_admin','Database Governance Administration','Owns migration history, DDL audit, data dictionary, partition maintenance, architecture map, quality gates, backup/restore evidence, and database readiness views.','Database Governance','administration','critical',true,true,true,true,'governance_admin governs the database itself and should avoid owning business-domain execution facts.'),
('container_governance','Container Governance Subsystem','Owns specialized container/package/image governance, container execution environments, container-specific signatures, release gates, and supply-chain controls.','Platform Security','specialized_subsystem','high',true,true,true,true,'Specialized subsystem. It may align to core registry/evidence concepts but should not redefine core run evidence for BioDiscoveryAI scripts.'),
('governance_kernel','Enterprise Governance Kernel','Owns universal entities, global identity allocation, relationship engine, metadata registry, event framework, and temporal governance primitives.','Enterprise Architecture','enterprise_governance','high',true,true,true,false,'Enterprise-wide primitives. Core evidence may reference these later, but current evidence identity remains registry.actors.'),
('governance_platform','Governance Platform Services','Owns rules, workflows, analytics, recommendations, simulations, semantic reasoning, and assistant platform services.','Enterprise Platform','platform_service','medium',true,true,false,false,'Platform services should consume governed evidence through views/contracts rather than duplicating regulated evidence.'),
('governance_contracts','Governance Contracts','Owns API, CLI, generator, validation, dashboard, SOP, and runbook contracts.','Architecture Review Board','enterprise_governance','high',true,true,false,false,'Contracts define expected behavior and validation assets. They may reference evidence outcomes through reports or validation records.'),
('governance_os','Enterprise Governance OS','Owns higher-level enterprise governance operating model and autonomous governance records.','Enterprise Governance','enterprise_governance','medium',true,true,false,false,'Enterprise operating layer; should depend on lower-level governance kernel/platform contracts.'),
('governance_marketplace','Governance Marketplace','Owns marketplace entries and review records for reusable governance assets.','Enterprise Governance','marketplace','medium',true,true,false,false,'Marketplace should reference approved contracts/assets, not regulated run evidence directly unless through reporting views.'),
('governance_federation','Multi-Enterprise Federation','Owns federation participants, federated identity mappings, and cross-enterprise sharing rules.','Enterprise Architecture','external_integration','high',true,true,true,true,'Federation may reference identity and contracts. Direct access to regulated evidence requires explicit review.'),
('governance_lakehouse','Governance Lakehouse','Owns analytics/lakehouse zones, marts, retention zones, and downstream BI metadata.','Data Platform','platform_service','medium',true,true,false,false,'Lakehouse stores analytic projections. It must not be treated as the authoritative source of regulated evidence.'),
('governance_streaming','Governance Event Streaming','Owns streaming topics, subscriptions, replay policies, and event pipeline governance.','Data Platform','platform_service','medium',true,true,false,false,'Streaming transports events. Authoritative event evidence remains in evidence/governance_admin as appropriate.'),
('regulatory_intelligence','Regulatory Intelligence','Owns regulatory source monitoring, interpretation, and intelligence records.','Regulatory Affairs','enterprise_governance','high',true,true,false,false,'Regulatory intelligence may inform controls and contracts, but does not own execution evidence.'),
('governance_twin','Governance Digital Twin','Owns digital-twin models and simulated governance state.','Enterprise Architecture','enterprise_governance','medium',true,true,false,false,'Digital twin is analytical/simulation-oriented. It should consume evidence, not replace it.'),
('strategic_governance','Strategic Governance','Owns strategic planning and portfolio-level governance records.','Executive Governance','enterprise_governance','medium',true,true,false,false,'Strategic layer consumes summarized evidence and readiness metrics.'),
('cognitive_governance','Enterprise Cognitive Layer','Owns cognitive/AI-assisted governance layer records.','AI Governance','platform_service','high',true,true,false,true,'Cognitive governance may interact with AI agents and recommendations; regulated actions still require evidence approvals/signatures.')
ON CONFLICT (schema_name) DO UPDATE SET
    domain_name = EXCLUDED.domain_name,
    responsibility_summary = EXCLUDED.responsibility_summary,
    owning_role = EXCLUDED.owning_role,
    system_layer = EXCLUDED.system_layer,
    regulated_criticality = EXCLUDED.regulated_criticality,
    allowed_to_own_operational_data = EXCLUDED.allowed_to_own_operational_data,
    allowed_to_own_reference_data = EXCLUDED.allowed_to_own_reference_data,
    allowed_to_own_audit_data = EXCLUDED.allowed_to_own_audit_data,
    allowed_to_own_security_controls = EXCLUDED.allowed_to_own_security_controls,
    lifecycle_status = EXCLUDED.lifecycle_status,
    boundary_notes = EXCLUDED.boundary_notes,
    updated_at = now();

INSERT INTO governance_admin.schema_reference_rules (
    source_schema, target_schema, reference_type, allowed, enforcement_level, rationale, review_required
)
VALUES
('evidence','registry','foreign_key',true,'database_enforced','Run evidence must reference controlled registry entities such as scripts, modules, actors, vocabularies, and environments.',false),
('archive','evidence','foreign_key',true,'database_enforced','Artifacts may reference the run that produced them.',false),
('archive','registry','foreign_key',true,'database_enforced','Artifacts must reference registered artifact types and controlled vocabularies.',false),
('reporting','evidence','foreign_key',true,'database_enforced','Reports may reference execution runs and evidence records.',false),
('signing','evidence','foreign_key',true,'database_enforced','Signed snapshots may reference the run or package being signed.',false),
('retention','evidence','foreign_key',true,'database_enforced','Retention workflows may reference approvals and evidence entities.',false),
('retention','registry','foreign_key',true,'database_enforced','Retention workflows may reference actors and controlled retention periods.',false),
('governance_admin','registry','admin_metadata',true,'architectural','Database governance metadata may classify registry objects.',false),
('governance_admin','evidence','admin_metadata',true,'architectural','Database governance metadata may assess evidence readiness, constraints, audit health, and backup/restore state.',false),
('governance_admin','archive','admin_metadata',true,'architectural','Database governance metadata may assess artifact retention and integrity.',false),
('governance_admin','retention','admin_metadata',true,'architectural','Database governance metadata may assess retention readiness.',false),
('container_governance','registry','contract_reference',true,'review_required','Container governance may align to core registry terms, but shared concepts require architecture review to avoid duplication.',true),
('container_governance','evidence','read_only_view',true,'review_required','Container governance may consume run evidence through approved views/contracts, not by redefining core evidence.',true),
('governance_kernel','registry','contract_reference',true,'review_required','Enterprise identity/entity primitives may be linked to core registry only through reviewed mapping contracts.',true),
('governance_platform','evidence','read_only_view',true,'review_required','Platform services may consume evidence through approved read-only views.',true),
('governance_contracts','evidence','read_only_view',true,'review_required','Contracts and validation suites may inspect evidence outcomes through approved views.',true),
('governance_lakehouse','evidence','read_only_view',true,'review_required','Lakehouse projections may consume regulated evidence through governed views or exports.',true),
('governance_streaming','evidence','event_reference',true,'review_required','Streaming may transport evidence events but must not become the system of record.',true),
('governance_federation','evidence','read_only_view',true,'review_required','Federated consumers require explicit review before reading regulated evidence.',true),
('evidence','container_governance','foreign_key',false,'prohibited','Core run evidence must not depend on specialized container governance tables; use registry/evidence as the stable core.',true),
('registry','evidence','foreign_key',false,'prohibited','Registry reference data must not depend on high-growth runtime evidence.',true),
('registry','archive','foreign_key',false,'prohibited','Registry reference data must not depend on artifact archive records.',true),
('registry','reporting','foreign_key',false,'prohibited','Registry reference data must not depend on generated reports.',true),
('registry','retention','foreign_key',false,'prohibited','Registry reference data must not depend on retention workflow records.',true),
('reporting','archive','foreign_key',true,'review_required','Reports may reference artifacts only when a report is explicitly artifact-backed.',true)
ON CONFLICT (source_schema, target_schema, reference_type) DO UPDATE SET
    allowed = EXCLUDED.allowed,
    enforcement_level = EXCLUDED.enforcement_level,
    rationale = EXCLUDED.rationale,
    review_required = EXCLUDED.review_required,
    active = EXCLUDED.active;

CREATE OR REPLACE VIEW governance_admin.schema_architecture_boundaries AS
SELECT
    m.schema_name,
    m.domain_name,
    m.system_layer,
    m.owning_role,
    m.regulated_criticality,
    m.lifecycle_status,
    m.responsibility_summary,
    m.boundary_notes
FROM governance_admin.schema_architecture_map m
ORDER BY
    CASE m.system_layer
        WHEN 'core_registry' THEN 1
        WHEN 'core_evidence' THEN 2
        WHEN 'artifact_archive' THEN 3
        WHEN 'signing' THEN 4
        WHEN 'retention' THEN 5
        WHEN 'reporting' THEN 6
        WHEN 'api_contract' THEN 7
        WHEN 'administration' THEN 8
        WHEN 'specialized_subsystem' THEN 9
        ELSE 10
    END,
    m.schema_name;

CREATE OR REPLACE VIEW governance_admin.prohibited_schema_reference_rules AS
SELECT *
FROM governance_admin.schema_reference_rules
WHERE allowed = false OR enforcement_level = 'prohibited';

CREATE OR REPLACE VIEW governance_admin.schema_reference_review_queue AS
SELECT *
FROM governance_admin.schema_reference_rules
WHERE active = true
  AND review_required = true;

COMMENT ON TABLE governance_admin.schema_architecture_map IS
'Architecture ownership map defining each schema domain, responsibility, owner, criticality, and boundary notes.';

COMMENT ON TABLE governance_admin.schema_reference_rules IS
'Allowed and prohibited cross-schema reference rules used to guide future additive database design.';

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (108, '108', 'Schema architecture map and reference rules', 'V108__schema_architecture_map_and_reference_rules.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
