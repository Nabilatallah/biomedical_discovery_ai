-- ============================================================================
-- BioDiscoveryAI Retention and Legal Hold Enforcement
-- Migration: V097__retention_legal_hold_enforcement.sql
-- ============================================================================

BEGIN;

ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS retention_until DATE;
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS archive_state TEXT NOT NULL DEFAULT 'active';
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS disposition_eligible_at TIMESTAMPTZ;
ALTER TABLE archive.artifacts ADD COLUMN IF NOT EXISTS legal_hold_reason TEXT;

ALTER TABLE archive.artifacts DROP CONSTRAINT IF EXISTS chk_artifacts_archive_state;
ALTER TABLE archive.artifacts ADD CONSTRAINT chk_artifacts_archive_state CHECK (archive_state IN ('active','archived','legal_hold','pending_disposition','disposed','superseded')) NOT VALID;

CREATE TABLE IF NOT EXISTS retention.retention_policies (
    retention_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_code TEXT NOT NULL UNIQUE,
    entity_type TEXT NOT NULL,
    retention_period TEXT NOT NULL REFERENCES registry.retention_periods(retention_period_code),
    minimum_months INT CHECK (minimum_months IS NULL OR minimum_months > 0),
    disposition_action TEXT NOT NULL CHECK (disposition_action IN ('retain','archive','delete_after_approval','anonymize_after_approval','transfer_to_cold_storage')),
    legal_basis TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS retention.legal_holds (
    legal_hold_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hold_code TEXT NOT NULL UNIQUE,
    related_entity_type TEXT NOT NULL,
    related_entity_id TEXT NOT NULL,
    hold_reason TEXT NOT NULL,
    hold_status TEXT NOT NULL DEFAULT 'active' CHECK (hold_status IN ('active','released','superseded')),
    placed_by TEXT REFERENCES registry.actors(actor_id),
    placed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    released_by TEXT REFERENCES registry.actors(actor_id),
    released_at TIMESTAMPTZ,
    release_reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT chk_legal_hold_release_fields CHECK (hold_status <> 'released' OR (released_by IS NOT NULL AND released_at IS NOT NULL AND release_reason IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS retention.retention_enforcement_queue (
    retention_queue_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    related_entity_type TEXT NOT NULL,
    related_entity_id TEXT NOT NULL,
    retention_policy_id UUID REFERENCES retention.retention_policies(retention_policy_id),
    due_at TIMESTAMPTZ NOT NULL,
    queue_status TEXT NOT NULL DEFAULT 'pending' CHECK (queue_status IN ('pending','blocked_by_hold','approved','executed','cancelled','failed')),
    blocked_reason TEXT,
    approval_id UUID REFERENCES evidence.approvals(approval_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(related_entity_type, related_entity_id, retention_policy_id)
);

CREATE TABLE IF NOT EXISTS retention.disposition_records (
    disposition_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retention_queue_id UUID NOT NULL REFERENCES retention.retention_enforcement_queue(retention_queue_id),
    disposition_action TEXT NOT NULL,
    disposition_status TEXT NOT NULL CHECK (disposition_status IN ('planned','executed','failed','reversed')),
    executed_by TEXT REFERENCES registry.actors(actor_id),
    executed_at TIMESTAMPTZ,
    evidence_uri TEXT,
    evidence_sha256 TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_artifacts_retention_until ON archive.artifacts(retention_until);
CREATE INDEX IF NOT EXISTS idx_artifacts_archive_state ON archive.artifacts(archive_state);
CREATE INDEX IF NOT EXISTS idx_legal_holds_entity ON retention.legal_holds(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_legal_holds_status ON retention.legal_holds(hold_status);
CREATE INDEX IF NOT EXISTS idx_retention_queue_due ON retention.retention_enforcement_queue(due_at, queue_status);

INSERT INTO retention.retention_policies(policy_code, entity_type, retention_period, minimum_months, disposition_action, legal_basis)
VALUES
('evidence_audit_events_7_years','audit_event','7_years',84,'archive','GxP and 21 CFR Part 11 audit evidence retention.'),
('evidence_artifacts_7_years','artifact','7_years',84,'archive','Scientific evidence and regulated artifact retention.'),
('validation_records_10_years','validation_record','10_years',120,'archive','Validation lifecycle evidence retention.'),
('signed_snapshots_10_years','evidence_snapshot','10_years',120,'archive','Signed evidence package retention.')
ON CONFLICT (policy_code) DO NOTHING;

INSERT INTO governance_admin.schema_migrations (installed_rank, version, description, script, success)
VALUES (97, '097', 'Retention and legal hold enforcement', 'V097__retention_legal_hold_enforcement.sql', true)
ON CONFLICT (version) DO NOTHING;

COMMIT;
