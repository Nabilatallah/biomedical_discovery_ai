# BioDiscoveryAI Governance Migration Bundle

This folder is the reproducible migration bundle built from:

`C:\biodiscovery\BDAI_Done\governance`

The source archive keeps historical package names such as `V011`, `V015`, and
`V091`. This bundle renumbers them into one consecutive Flyway-compatible
sequence:

```text
V001 ... V102
```

Original source versions and file paths are preserved in `manifest.csv` and
`manifest.json`.

## Contents

- `migrations/` - ordered versioned SQL migrations
- `seeds/` - repeatable reference/demo seed SQL
- `validation/validate_schema.sql` - database-level smoke validation
- `validation/python/validate_governance_schema.py` - deeper schema/function/trigger validation
- `apps/governance-api/` - FastAPI runtime API for governed table access
- `manifest.csv` - canonical mapping from bundle file to source file
- `docker-compose.yml` - local PostgreSQL, Flyway runner, validator, and governance API
- `flyway.conf` - Flyway defaults for this bundle

## Canonical Status

This directory is the canonical deployable Flyway bundle. The repository also
keeps `sql_hardening_migrations/` as source/reference material for the original
hardening layer `V091` through `V108`; those files are not a separate deployment
chain. The builder renumbers that hardening layer into this bundle as `V085`
through `V102`, with provenance recorded in `manifest.csv` and `manifest.json`.

## Static Validation

Run this first. It does not require PostgreSQL or Docker.

```powershell
.\tools\lint_governance_migration_bundle.ps1
```

It checks:

- migration versions are consecutive
- migration filenames are unique
- manifest rows match files on disk
- the expected seed file exists

## Database Validation

Run against Docker Compose:

```powershell
cd .\governance_migration_bundle
docker compose up -d postgres
docker compose run --rm flyway migrate
docker compose exec -T postgres psql -U bdai -d biodiscoveryai -f /validation/validate_schema.sql
docker compose run --rm governance-validator
docker compose up -d governance-api
```

Or from the repository root:

```powershell
.\tools\validate_governance_migration_bundle.ps1
```

Keep the migrated database and API running for inspection:

```powershell
.\tools\validate_governance_migration_bundle.ps1 -KeepRunning
```

The API will be available at:

```text
http://localhost:8008
```

## Regression Validation

Run this when changing migration sources, builder logic, validation, or bundle
contents:

```powershell
.\tools\test_governance_migration_regression.ps1
```

It rebuilds a temporary bundle from the source archive, lints it, verifies the
generated migrations/seeds/manifests match the committed bundle, and runs the
full Docker/Flyway/Postgres validation against the rebuilt bundle.

## Notes

- This bundle intentionally skips archived design-history migrations `V012` and
  `V014` from the original container-governance package because `V015` is the
  production merged layer called out by the source docs.
- The original `V015` layer repeats several `V011` objects even though the docs
  say to run `V011` first. The builder patches the copied bundle migration to
  use idempotent `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`
  statements in that repeated block. The source archive is not modified.
- The bundled seed is repeatable and intended for dev/reference validation.
- Passing this validation proves the SQL chain applies and core objects exist.
  It does not replace GxP validation, security review, performance/load testing,
  backup/restore drills, or SOP approval.
