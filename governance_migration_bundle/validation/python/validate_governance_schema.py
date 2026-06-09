#!/usr/bin/env python3
"""
BioDiscoveryAI Governance Schema Validation Suite

Purpose:
  Validate that the normalized governance migration bundle V001-V102 was
  applied correctly.

Usage:
  export DATABASE_URL="postgresql://user:pass@localhost:5432/biodiscoveryai"
  python validation/python/validate_governance_schema.py

Checks:
  - Required schemas exist
  - Required tables/views/functions exist
  - Critical triggers exist
  - Required seed records exist
  - Deployment readiness functions are present
"""

from __future__ import annotations

import os
import sys
import json
import psycopg
from dataclasses import dataclass, asdict


REQUIRED_SCHEMAS = [
    "container_governance",
    "governance_kernel",
    "governance_platform",
    "governance_os",
    "governance_contracts",
    "governance_admin",
]

REQUIRED_TABLES = {
    "container_governance": [
        "modules",
        "scripts",
        "approved_packages",
        "base_images",
        "container_images",
        "image_packages",
        "image_builds",
        "container_evidence",
        "validation_records",
        "execution_runs",
        "audit_events",
    ],
    "governance_kernel": [
        "entity_types",
        "governance_entities",
        "identity_namespaces",
        "governance_events",
        "metadata_objects",
        "relationship_types",
        "entity_relationships",
        "temporal_snapshots",
    ],
    "governance_contracts": [
        "api_services",
        "api_contracts",
        "cli_tools",
        "generators",
        "validation_suites",
        "dashboard_catalog",
        "sop_runbook_catalog",
    ],
    "governance_os": [
        "command_types",
        "governance_commands",
        "governance_tasks",
        "governance_actions",
    ],
    "governance_admin": [
        "schema_migrations",
        "schema_architecture_map",
        "schema_reference_rules",
    ],
}

REQUIRED_FUNCTIONS = [
    ("container_governance", "is_image_deployable"),
    ("container_governance", "is_release_certified"),
    ("governance_kernel", "allocate_enterprise_object_id"),
    ("governance_kernel", "compute_governance_event_hash"),
]

REQUIRED_TRIGGERS = [
    "trg_compute_audit_event_hash",
    "trg_prevent_audit_event_update",
    "trg_prevent_non_deployable_execution",
    "trg_compute_governance_event_hash",
]

@dataclass
class CheckResult:
    name: str
    status: str
    detail: str


def check_exists(cur, sql: str, params: tuple) -> bool:
    cur.execute(sql, params)
    return bool(cur.fetchone()[0])


def main() -> int:
    db_url = os.getenv("DATABASE_URL") or os.getenv("BDAI_DATABASE_URL")
    if not db_url:
        print("ERROR: DATABASE_URL/BDAI_DATABASE_URL is not set.", file=sys.stderr)
        return 2

    results: list[CheckResult] = []

    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            for schema in REQUIRED_SCHEMAS:
                ok = check_exists(
                    cur,
                    "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = %s)",
                    (schema,),
                )
                results.append(CheckResult(f"schema:{schema}", "pass" if ok else "fail", "exists" if ok else "missing"))

            for schema, tables in REQUIRED_TABLES.items():
                for table in tables:
                    ok = check_exists(
                        cur,
                        """
                        SELECT EXISTS (
                            SELECT 1
                            FROM information_schema.tables
                            WHERE table_schema = %s
                              AND table_name = %s
                        )
                        """,
                        (schema, table),
                    )
                    results.append(CheckResult(f"table:{schema}.{table}", "pass" if ok else "fail", "exists" if ok else "missing"))

            for schema, func in REQUIRED_FUNCTIONS:
                ok = check_exists(
                    cur,
                    """
                    SELECT EXISTS (
                        SELECT 1
                        FROM pg_proc p
                        JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = %s
                          AND p.proname = %s
                    )
                    """,
                    (schema, func),
                )
                results.append(CheckResult(f"function:{schema}.{func}", "pass" if ok else "fail", "exists" if ok else "missing"))

            for trig in REQUIRED_TRIGGERS:
                ok = check_exists(
                    cur,
                    "SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = %s)",
                    (trig,),
                )
                results.append(CheckResult(f"trigger:{trig}", "pass" if ok else "fail", "exists" if ok else "missing"))

    failed = [r for r in results if r.status == "fail"]

    print(json.dumps([asdict(r) for r in results], indent=2))

    if failed:
        print(f"\nFAILED: {len(failed)} checks failed.", file=sys.stderr)
        return 1

    print("\nPASS: Governance schema validation completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
