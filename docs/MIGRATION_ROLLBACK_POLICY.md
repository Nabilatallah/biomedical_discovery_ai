# Migration Rollback And Recovery Policy

## Policy

Governance migrations are forward-only. Failed migrations are corrected by one
of three controlled recovery paths:

1. Restore from a validated backup when a failed migration may have partially
   changed durable data.
2. Apply a forward-fix migration when the database is still consistent and the
   fix can be expressed as auditable DDL/DML.
3. Use break-glass access only under incident control, then record a controlled
   correction and follow with a normal migration.

## Pre-Migration Requirements

- Run static lint.
- Run API contract tests.
- Run full Docker/Flyway/Postgres validation.
- Run warning-registry enforcement.
- Generate a release evidence packet.
- Capture a backup or restore point for the target environment.

## Failed Migration Handling

| Failure point | Response |
| --- | --- |
| Migration fails before commit | Investigate, correct migration, rerun in a clean environment. |
| Migration fails after partial data change | Restore from the pre-migration backup, then apply corrected migration. |
| Migration succeeds but validation fails | Treat as failed release; restore or apply a forward-fix after impact assessment. |
| Post-release defect is found | Create a new migration with explicit correction evidence; do not rewrite applied migrations. |

## Backup And Restore Evidence

`tools/test_backup_restore_drill.ps1` creates a migrated database, dumps it,
restores it into a second database, and reruns schema/authorization validation.
This drill must pass before promotion.

## Break-Glass Rules

`bdai_break_glass` is intended for controlled emergency operations only. Use
must be approved, time-bounded, logged, and followed by a normal migration or
controlled correction record that explains the reason, operator, timestamp,
affected objects, and validation performed afterward.
