from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
from fastapi.testclient import TestClient

from src.main import app


client = TestClient(app)


ISSUER = "https://auth.test/bdai"
AUDIENCE = "biodiscoveryai-governance"
SECRET = "unit-test-secret"


def configure_auth(monkeypatch):
    monkeypatch.setenv("GOVERNANCE_JWT_ISSUER", ISSUER)
    monkeypatch.setenv("GOVERNANCE_JWT_AUDIENCE", AUDIENCE)
    monkeypatch.setenv("GOVERNANCE_JWT_HS256_SECRET", SECRET)
    monkeypatch.delenv("GOVERNANCE_OIDC_JWKS_URI", raising=False)


def bearer_token(
    *,
    subject: str = "user-123",
    roles: list[str] | None = None,
    scopes: list[str] | None = None,
    issuer: str = ISSUER,
    audience: str = AUDIENCE,
) -> str:
    now = datetime.now(timezone.utc)
    claims = {
        "iss": issuer,
        "aud": audience,
        "sub": subject,
        "iat": now,
        "exp": now + timedelta(minutes=15),
        "roles": roles or [],
        "scope": " ".join(scopes or []),
    }
    return jwt.encode(claims, SECRET, algorithm="HS256")


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def valid_package_payload() -> dict[str, str]:
    return {
        "package_manager": "pip",
        "package_name": "numpy",
        "package_version": "2.2.0",
        "package_description": "Numerical computing package",
        "inclusion_reason": "Required for scientific workloads",
        "functional_role": "array-processing",
        "security_risk_level": "low",
        "package_sha256": "a" * 64,
    }


def valid_evidence_payload() -> dict[str, str]:
    return {
        "image_id": str(uuid4()),
        "evidence_type": "sbom",
        "evidence_tool": "syft",
        "evidence_uri": "s3://example/evidence.json",
        "evidence_sha256": "b" * 64,
        "pass_fail_status": "pass",
        "generated_by": "ci",
    }


def test_health_is_open_without_database_or_token(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("BDAI_DATABASE_URL", raising=False)
    monkeypatch.delenv("GOVERNANCE_JWT_ISSUER", raising=False)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_data_endpoints_require_bearer_token(monkeypatch):
    configure_auth(monkeypatch)

    response = client.get(f"/images/{uuid4()}/deployable")

    assert response.status_code == 401


def test_invalid_issuer_is_rejected(monkeypatch):
    configure_auth(monkeypatch)
    token = bearer_token(issuer="https://wrong-issuer")

    response = client.get(f"/images/{uuid4()}/deployable", headers=auth_header(token))

    assert response.status_code == 401


def test_under_scoped_writer_is_forbidden_before_database(monkeypatch):
    configure_auth(monkeypatch)
    token = bearer_token(roles=["governance_reader"], scopes=["governance:read"])

    response = client.post(
        "/evidence",
        json=valid_evidence_payload(),
        headers=auth_header(token),
    )

    assert response.status_code == 403


def test_payload_validation_rejects_bad_sha256_before_database(monkeypatch):
    configure_auth(monkeypatch)
    token = bearer_token(roles=["package_writer"])

    payload = valid_package_payload()
    payload["package_sha256"] = "not-a-sha"
    response = client.post("/packages", json=payload, headers=auth_header(token))

    assert response.status_code == 422
