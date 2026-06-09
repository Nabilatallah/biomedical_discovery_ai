from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from jwt import PyJWK

from src import main
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


def rsa_key_pair(kid: str):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(private_key.public_key()))
    public_jwk.update({"kid": kid, "use": "sig", "alg": "RS256"})
    return private_key, public_jwk


class RotatingJwksClient:
    def __init__(self, keys: dict[str, dict[str, str]]):
        self.keys = keys

    def get_signing_key_from_jwt(self, token: str):
        kid = jwt.get_unverified_header(token)["kid"]
        return PyJWK(self.keys[kid])


def rs256_token(private_key, kid: str, *, roles: list[str] | None = None) -> str:
    now = datetime.now(timezone.utc)
    claims = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "sub": f"oidc-user-{kid}",
        "iat": now,
        "exp": now + timedelta(minutes=15),
        "roles": roles or ["governance_reader"],
    }
    return jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": kid})


def test_oidc_jwks_accepts_rotated_signing_keys(monkeypatch):
    monkeypatch.setenv("GOVERNANCE_JWT_ISSUER", ISSUER)
    monkeypatch.setenv("GOVERNANCE_JWT_AUDIENCE", AUDIENCE)
    monkeypatch.setenv("GOVERNANCE_OIDC_JWKS_URI", "https://auth.test/.well-known/jwks.json")
    monkeypatch.delenv("GOVERNANCE_JWT_HS256_SECRET", raising=False)

    old_private, old_public = rsa_key_pair("old-key")
    new_private, new_public = rsa_key_pair("new-key")
    monkeypatch.setattr(
        main,
        "jwks_client",
        lambda _uri: RotatingJwksClient({"old-key": old_public, "new-key": new_public}),
    )

    old_principal = main.current_principal(type("Creds", (), {"scheme": "Bearer", "credentials": rs256_token(old_private, "old-key")})())
    new_principal = main.current_principal(type("Creds", (), {"scheme": "Bearer", "credentials": rs256_token(new_private, "new-key")})())

    assert old_principal.subject == "oidc-user-old-key"
    assert new_principal.subject == "oidc-user-new-key"
