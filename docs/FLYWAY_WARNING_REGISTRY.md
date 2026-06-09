# Flyway Warning Registry

The governance bundle is expected to run with PostgreSQL notices because many
source migrations are intentionally idempotent. Validation fails on SQL errors;
these warning classes are tracked so expected noise does not hide real drift.

## Expected Warning Classes

| Warning class | Source | Current handling |
| --- | --- | --- |
| `extension "pgcrypto" already exists, skipping` | Later migrations defensively enable `pgcrypto` after `V001`. | Accepted idempotency notice. |
| `schema "..." already exists, skipping` | Domain migrations defensively create schemas before adding objects. | Accepted idempotency notice. Flyway now owns only `public` so it no longer pre-creates application schemas. |
| `relation "..." already exists, skipping` | The consolidated container governance layer repeats selected objects from earlier source layers. | Accepted only where source history intentionally overlaps; the builder patches repeated container governance DDL to `IF NOT EXISTS`. |
| `trigger "..." does not exist, skipping` | Migrations drop and recreate triggers for deterministic definitions. | Accepted when immediately followed by trigger/function recreation in the same migration family. |
| `constraint "..." does not exist, skipping` | Hardening migrations normalize constraint definitions with defensive drops. | Accepted when followed by replacement constraint creation or validation. |
| `policy "..." does not exist, skipping` | RLS migrations defensively recreate policies. | Accepted when policy creation follows in the same migration. |
| `there is already a transaction in progress` | Some source migrations include transaction control while Flyway is already executing transactionally. | Accepted migration-source debt; target for future source cleanup. |

## Reduced Warning Noise

`flyway.conf` now sets `flyway.schemas=public`. Flyway owns only the schema
history schema; application schemas are created by versioned migrations. This
removes the avoidable warnings where Flyway created application schemas before
`V001` ran.

## Triage Rule

Any new warning outside this registry should be treated as a review item before
promotion. The full validation command remains:

```powershell
.\tools\validate_governance_migration_bundle.ps1
```
