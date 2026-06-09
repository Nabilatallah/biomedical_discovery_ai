# Governance Platform Threat Model

## Scope

This threat model covers the governance migration bundle, PostgreSQL schemas,
FastAPI governance API, validation tooling, release evidence generation, Docker
runtime, and local/CI execution paths.

## Primary Assets

| Asset | Protection goal |
| --- | --- |
| Evidence and audit tables | Append-only integrity, non-repudiation, traceability |
| Governance schema migrations | Reproducible deployment and controlled change |
| API write paths | Authenticated, authorized, attributable mutation |
| Container provenance | Verifiable image/package/evidence lineage |
| Secrets and tokens | No source-control exposure, short-lived use, rotation |
| Backup artifacts | Recoverable, validated, protected from tampering |

## Trust Boundaries

| Boundary | Control |
| --- | --- |
| API caller to API | OIDC/JWT bearer validation with issuer, audience, role, and scope checks |
| API to database | `SET ROLE` into least-privilege runtime/read-only roles plus caller propagation through `app.actor`, `app.roles`, and `app.scopes` |
| Migration runner to database | Dedicated migration context and immutable Flyway history |
| CI runner to Docker stack | Ephemeral PostgreSQL containers and full validation before promotion |
| Source archive to deployable bundle | Manifest provenance and rebuild regression |

## Threats And Mitigations

| Threat | Mitigation |
| --- | --- |
| Forged API token | Validate JWT signature, issuer, audience, expiration, and subject. Production should use `GOVERNANCE_OIDC_JWKS_URI`; HS256 is for dev/test only. |
| Over-scoped API caller | Per-action role/scope checks for read, package write, and evidence write paths. |
| API bypasses authorization by using owner privileges | API connections immediately `SET ROLE` into `bdai_app_runtime` or `bdai_readonly`; validation proves runtime cannot insert into governance-admin tables. |
| Audit-chain tampering | Hash-chain triggers, append-only controls, controlled correction tables, and validation checks. |
| Direct table mutation outside API | Least-privilege roles, RLS policies, and negative authorization validation. Production must not expose migration credentials to app runtime. |
| Supply-chain ambiguity | Package, image, build, evidence, release certification, and manifest provenance tables. |
| Secret leakage | Local secret scan, documented dev-only secrets, and production secret manager requirement. |
| Unrecoverable failed migration | Restore-point policy, backup/restore drill automation, and forward-fix migration policy. |
| Silent migration warning drift | Warning registry enforcement fails CI on unregistered warning classes. |
| Lost validation evidence | Release evidence packet captures commit, migration count, manifest hash, validation log hash, and control commands. |

## Residual Risk

This repository provides local and CI-verifiable controls. Production deployment
still requires an actual identity provider, managed secret store, network
policy, production database role provisioning, log retention, backup retention,
and incident-response ownership.
