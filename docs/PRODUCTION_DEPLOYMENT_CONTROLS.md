# Production Deployment Controls

This repository is wired for production-style controls without storing production credentials.

## Identity

- `GOVERNANCE_JWT_ISSUER` must be the production OIDC issuer.
- `GOVERNANCE_JWT_AUDIENCE` must match the API audience configured in the identity provider.
- `GOVERNANCE_OIDC_JWKS_URI` must point to the provider JWKS endpoint.
- `GOVERNANCE_JWT_HS256_SECRET` is allowed only for local development and unit tests.

## Secrets

Production values must be supplied by one of:

- GitHub Actions encrypted secrets for CI-only values.
- A cloud secret manager for deployed workloads.
- Vault, Doppler, or 1Password Secrets Automation.

Real secrets are not allowed in source, images, evidence packets, or logs. `tools/scan_secrets.ps1` enforces committed-secret checks in CI.

## Branch Protection

Required GitHub branch protection for `main`:

- Require the `Governance Migration Validation` workflow to pass.
- Require pull request review before merge.
- Block force pushes.
- Block branch deletion.
- Require conversation resolution before merge.

Apply with:

```powershell
$env:GITHUB_TOKEN = "<admin-scoped token from a secret manager>"
./tools/apply_github_branch_protection.ps1 -Repository Nabilatallah/biomedical_discovery_ai -Branch main
```

## Staging Smoke Test

The CI staging smoke step runs only when these GitHub Actions secrets are configured:

- `STAGING_GOVERNANCE_API_URL`
- `STAGING_GOVERNANCE_BEARER_TOKEN`

The token must be issued by the production-like IdP and include at least `governance:read`.
