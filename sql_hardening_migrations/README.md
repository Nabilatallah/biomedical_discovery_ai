# SQL Hardening Migrations

This directory is retained as source/reference material for the hardening layer
originally versioned as `V091` through `V108`.

The canonical deployable Flyway sequence is:

```text
governance_migration_bundle/migrations/V001 ... V102
```

During bundle generation, `tools/build_governance_migration_bundle.ps1` reads
the hardening source files and renumbers them into the consecutive bundle range
`V085` through `V102`. The source-to-bundle mapping is recorded in
`governance_migration_bundle/manifest.csv` and
`governance_migration_bundle/manifest.json`.

Do not run this directory directly against the bundled database. Use it only to
inspect the original hardening-layer SQL or to refresh the canonical bundle
through the builder.
