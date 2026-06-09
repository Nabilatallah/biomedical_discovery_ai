CREATE TABLE IF NOT EXISTS registry.owners (
    owner_id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    role_name TEXT NOT NULL,
    email TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS registry.modules (
    module_id TEXT PRIMARY KEY,
    module_name TEXT NOT NULL,
    lifecycle_status TEXT NOT NULL,
    architectural_layer TEXT NOT NULL,
    owner_ref TEXT REFERENCES registry.owners(owner_id),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS registry.scripts (
    script_id TEXT PRIMARY KEY,
    document_id TEXT UNIQUE NOT NULL,
    script_name TEXT NOT NULL,
    module_id TEXT NOT NULL REFERENCES registry.modules(module_id),
    version TEXT NOT NULL,
    lifecycle_status TEXT NOT NULL,
    execution_type TEXT NOT NULL,
    entry_point BOOLEAN NOT NULL DEFAULT false,
    parent_workflow TEXT,
    owner_refs JSONB NOT NULL DEFAULT '{}'::jsonb,
    purpose JSONB NOT NULL DEFAULT '{}'::jsonb,
    regulated_use JSONB NOT NULL DEFAULT '{}'::jsonb,
    part11 JSONB NOT NULL DEFAULT '{}'::jsonb,
    security_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    privacy_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    validation_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    release_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
    execution_modes JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS registry.controls (
    control_id TEXT PRIMARY KEY,
    control_name TEXT NOT NULL,
    domain TEXT NOT NULL,
    purpose TEXT NOT NULL,
    owner_ref TEXT REFERENCES registry.owners(owner_id),
    frameworks TEXT[] NOT NULL DEFAULT '{}',
    evidence_patterns TEXT[] NOT NULL DEFAULT '{}',
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS registry.artifact_types (
    artifact_type_id TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    default_storage_location TEXT NOT NULL,
    store_body_in_db BOOLEAN NOT NULL DEFAULT false,
    retention_period TEXT NOT NULL DEFAULT '7_years',
    legal_hold_supported BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
