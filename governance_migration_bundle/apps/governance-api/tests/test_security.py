from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from src.main import app


client = TestClient(app)


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


def test_health_is_open_without_database_or_api_key(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("BDAI_DATABASE_URL", raising=False)
    monkeypatch.delenv("GOVERNANCE_API_KEYS", raising=False)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_write_endpoints_require_configured_api_keys(monkeypatch):
    monkeypatch.delenv("GOVERNANCE_API_KEYS", raising=False)

    response = client.post("/packages", json=valid_package_payload())

    assert response.status_code == 503
    assert "GOVERNANCE_API_KEYS" in response.json()["detail"]


def test_write_endpoints_reject_missing_or_invalid_api_key(monkeypatch):
    monkeypatch.setenv("GOVERNANCE_API_KEYS", "secret-1,secret-2")

    missing = client.post("/packages", json=valid_package_payload())
    invalid = client.post(
        "/evidence",
        json=valid_evidence_payload(),
        headers={"X-Governance-API-Key": "wrong"},
    )

    assert missing.status_code == 401
    assert invalid.status_code == 401


def test_payload_validation_rejects_bad_sha256_before_database(monkeypatch):
    monkeypatch.setenv("GOVERNANCE_API_KEYS", "secret-1")

    payload = valid_package_payload()
    payload["package_sha256"] = "not-a-sha"
    response = client.post(
        "/packages",
        json=payload,
        headers={"X-Governance-API-Key": "secret-1"},
    )

    assert response.status_code == 422
