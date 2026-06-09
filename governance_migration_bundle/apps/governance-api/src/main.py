"""
BioDiscoveryAI Governance API

Purpose:
  Stable API layer for governance operations.
  Tools should use this API instead of directly mutating governance tables.

Run:
  export DATABASE_URL="postgresql://user:pass@localhost:5432/biodiscovery"
  uvicorn src.main:app --reload
"""

from __future__ import annotations

import os
import secrets
from typing import Any
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, Field


def database_url() -> str | None:
    return os.getenv("DATABASE_URL") or os.getenv("BDAI_DATABASE_URL")


def configured_api_keys() -> set[str]:
    raw = os.getenv("GOVERNANCE_API_KEYS", "")
    return {key.strip() for key in raw.split(",") if key.strip()}


def require_write_api_key(x_governance_api_key: str | None = Header(default=None)) -> None:
    keys = configured_api_keys()
    if not keys:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GOVERNANCE_API_KEYS is not configured for write operations",
        )
    if not x_governance_api_key or not any(
        secrets.compare_digest(x_governance_api_key, key) for key in keys
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Valid X-Governance-API-Key header is required",
        )


app = FastAPI(
    title="BioDiscoveryAI Governance API",
    version="1.0.0",
    description="Governed API for lineage, deployability, packages, images, evidence, and release readiness.",
)


class PackageCreate(BaseModel):
    package_manager: str = Field(min_length=1, max_length=64)
    package_name: str = Field(min_length=1, max_length=256)
    package_version: str = Field(min_length=1, max_length=128)
    package_description: str = Field(min_length=1, max_length=2000)
    inclusion_reason: str = Field(min_length=1, max_length=2000)
    functional_role: str = Field(min_length=1, max_length=256)
    security_risk_level: str = Field(pattern="^(low|medium|high|critical)$")
    license_name: str | None = Field(default=None, max_length=256)
    package_source_url: str | None = Field(default=None, max_length=2048)
    package_sha256: str | None = Field(default=None, pattern="^[A-Fa-f0-9]{64}$")


class EvidenceCreate(BaseModel):
    image_id: UUID
    build_id: UUID | None = None
    evidence_type: str = Field(min_length=1, max_length=128)
    evidence_tool: str = Field(min_length=1, max_length=128)
    evidence_uri: str = Field(min_length=1, max_length=2048)
    evidence_sha256: str = Field(pattern="^[A-Fa-f0-9]{64}$")
    evidence_summary: dict[str, Any] = Field(default_factory=dict, max_length=100)
    pass_fail_status: str = Field(pattern="^(pass|fail|warning|accepted_risk)$")
    generated_by: str = Field(min_length=1, max_length=256)


def conn():
    DATABASE_URL = database_url()
    if not DATABASE_URL:
        raise HTTPException(status_code=500, detail="DATABASE_URL/BDAI_DATABASE_URL is not configured")
    return psycopg.connect(DATABASE_URL, connect_timeout=5)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready")
def ready() -> dict[str, str]:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
    return {"status": "ready"}


@app.get("/images/{image_id}/deployable")
def image_deployable(image_id: UUID) -> dict[str, Any]:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("SELECT container_governance.is_image_deployable(%s)", (str(image_id),))
            result = cur.fetchone()
    return {"image_id": str(image_id), "deployable": bool(result[0]) if result else False}


@app.get("/images/{image_id}/release-certified")
def image_release_certified(image_id: UUID) -> dict[str, Any]:
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("SELECT container_governance.is_release_certified(%s)", (str(image_id),))
            result = cur.fetchone()
    return {"image_id": str(image_id), "release_certified": bool(result[0]) if result else False}


@app.get("/lineage/container/{image_id}")
def container_lineage(image_id: UUID) -> dict[str, Any]:
    with conn() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT *
                FROM container_governance.v_container_full_lineage
                WHERE image_id = %s
                """,
                (str(image_id),),
            )
            rows = cur.fetchall()
    return {"image_id": str(image_id), "lineage": rows}


@app.post("/packages", dependencies=[Depends(require_write_api_key)])
def create_package(payload: PackageCreate) -> dict[str, Any]:
    with conn() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                INSERT INTO container_governance.approved_packages (
                    package_manager,
                    package_name,
                    package_version,
                    package_description,
                    inclusion_reason,
                    functional_role,
                    security_risk_level,
                    license_name,
                    package_source_url,
                    package_sha256
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING package_id
                """,
                (
                    payload.package_manager,
                    payload.package_name,
                    payload.package_version,
                    payload.package_description,
                    payload.inclusion_reason,
                    payload.functional_role,
                    payload.security_risk_level,
                    payload.license_name,
                    payload.package_source_url,
                    payload.package_sha256,
                ),
            )
            row = cur.fetchone()
            c.commit()
    return {"package_id": str(row["package_id"])}


@app.post("/evidence", dependencies=[Depends(require_write_api_key)])
def register_evidence(payload: EvidenceCreate) -> dict[str, Any]:
    with conn() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                INSERT INTO container_governance.container_evidence (
                    image_id,
                    build_id,
                    evidence_type,
                    evidence_tool,
                    evidence_uri,
                    evidence_sha256,
                    evidence_summary,
                    pass_fail_status,
                    generated_by
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s::jsonb,%s,%s)
                RETURNING evidence_id
                """,
                (
                    str(payload.image_id),
                    str(payload.build_id) if payload.build_id else None,
                    payload.evidence_type,
                    payload.evidence_tool,
                    payload.evidence_uri,
                    payload.evidence_sha256,
                    Jsonb(payload.evidence_summary),
                    payload.pass_fail_status,
                    payload.generated_by,
                ),
            )
            row = cur.fetchone()
            c.commit()
    return {"evidence_id": str(row["evidence_id"])}
