#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/foundation_common.sh" ]]; then
  source "${SCRIPT_DIR}/foundation_common.sh"
elif [[ -f "${SCRIPT_DIR}/../01_foundation/foundation_common.sh" ]]; then
  source "${SCRIPT_DIR}/../01_foundation/foundation_common.sh"
else
  printf '[ERROR] foundation_common.sh not found beside B002 scripts or in ../01_foundation\n' >&2
  exit 1
fi
# ==============================================================================
# Developer Documentation Index for @FILE_NAME@
# ==============================================================================
#
# Section 01 - Design principles
#   Explains the SOLID-style architecture decisions used by this script family.
#   Single Responsibility keeps this script focused on @TITLE@ only. Open/Closed
#   behavior allows the component catalog to grow without rewriting the runtime
#   contract. Liskov-style substitution means every component exposes the same
#   baseline runtime surface: health, config, contract, policy, audit,
#   observability, validation, and evidence. Interface segregation keeps service,
#   SDK, data, infrastructure, and governance interfaces small. Dependency
#   inversion keeps downstream runtime deployment dependent on generated manifests
#   rather than hard-coded folders or cloud/HPC vendors.
#
# Section 02 - What this script does
#   @SUMMARY@
#   Phase: @PHASE@. Domain: @DOMAIN@. Workflow step: @WORKFLOW@.
#
# Section 03 - How To Run On HPC
#   Use this on HPC inside the approved foundation/runtime runner, with project
#   output on an approved absolute mounted path. Apptainer/Singularity is the
#   expected container runtime for regulated HPC environments.
#
#   Direct execution:
#     chmod +x /path/to/@FILE_NAME@
#     /path/to/@FILE_NAME@ --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /approved/project/storage
#
#   Slurm pattern:
#     sbatch <<'SLURM_EOF'
#     #!/bin/bash
#     #SBATCH --job-name=@SCRIPT_ID@
#     #SBATCH --time=00:10:00
#     #SBATCH --cpus-per-task=2
#     #SBATCH --mem=4G
#     /path/to/@FILE_NAME@ --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /approved/project/storage
#     SLURM_EOF
#
# Section 04 - How To Run On AWS Cloud
#   Use this on AWS inside the approved Docker foundation/runtime runner before
#   ECS, EKS, Batch, CodeBuild, or Terraform deploys the generated runtime.
#
#   Docker pattern:
#     docker run --rm \
#       -v "$PWD/out:/work" \
#       -v "$PWD:/workspace" \
#       biodiscoveryai/foundation-runner:0.3.0 \
#       /workspace/02_runtime/@FILE_NAME@ --project-name biodiscoveryai --target aws --container-runtime docker --output-root /work
#
#   AWS CodeBuild/Batch pattern:
#     /workspace/02_runtime/@FILE_NAME@ \
#       --project-name biodiscoveryai \
#       --target aws \
#       --container-runtime docker \
#       --output-root "$CODEBUILD_SRC_DIR/out" \
#       --image <aws_account_id>.dkr.ecr.<region>.amazonaws.com/biodiscoveryai/foundation-runner:0.3.0
#
# Section 05 - What It Does
#
# | Area                   | Capability                                                                                                  |
# |------------------------|-------------------------------------------------------------------------------------------------------------|
# | Runtime focus          | Implements the @TITLE@ runtime scaffold and machine-readable implementation catalog.                         |
# | Workflow step          | Supports @WORKFLOW@.                                                                                        |
# | Component boundaries   | Creates one runtime component lane per catalog entry with source, contract, policy, tests, and evidence.    |
# | Concrete skeletons     | Writes runnable Python/FastAPI-style module skeletons, health endpoints, tests, and runtime manifests.       |
# | Governance readiness   | Adds policy, audit, validation, risk, and observability placeholders for every runtime component.            |
# | Reporting              | Produces a human-readable Markdown execution report with start/end/duration/status.                          |
# | Auditability           | Produces JSONL audit events, checksums, artifact manifest, and optional signatures where tools are present.  |
# | Downstream integration | Generates catalog YAML/JSON artifacts that B002 orchestrator, CI, HPC, and AWS automation can consume.       |
#
# Section 06 - Artifacts Created When The Script Runs
#
# | Artifact name                                     | Purpose                                      | Dependency               | Importance score |
# |---------------------------------------------------|----------------------------------------------|--------------------------|-----------------:|
# | <project>/@ROOT@/<component>/component.yaml       | Machine-readable runtime component manifest | mkdir, cat, date         |               10 |
# | <project>/@ROOT@/<component>/README.md            | Human-readable component boundary           | mkdir, cat, date         |               10 |
# | <project>/@ROOT@/<component>/src/app.py           | Runnable Python/FastAPI-style skeleton      | cat                      |                9 |
# | <project>/@ROOT@/<component>/tests/test_health.py | Baseline health test                         | cat                      |                8 |
# | <project>/@ROOT@/<component>/contracts/openapi.yaml | Contract placeholder                       | cat                      |                9 |
# | <project>/.runtime/@EVIDENCE_NAME@/catalog.yaml   | Central runtime catalog                      | cat                      |               10 |
# | <project>/.runtime/@EVIDENCE_NAME@/catalog.json   | Machine-readable runtime catalog             | cat                      |               10 |
# | <project>/.runtime/@EVIDENCE_NAME@/report.md      | Markdown execution report                    | date, cat                |               10 |
# | <project>/.runtime/@EVIDENCE_NAME@/audit.jsonl    | JSONL execution audit trail                  | date, sed                |               10 |
# | <project>/.runtime/@EVIDENCE_NAME@/checksums.txt  | SHA-256 checksums for generated files        | sha256sum/shasum/openssl |               10 |
# | <project>/.runtime/@EVIDENCE_NAME@/manifest.jsonl | Canonical artifact manifest                  | sha256sum/shasum/openssl |               10 |
#
# Section 07 - Portability contract
#   Downstream scripts should read .runtime/@EVIDENCE_NAME@/catalog.yaml,
#   .runtime/@EVIDENCE_NAME@/catalog.json, and each component.yaml instead of
#   hard-coding runtime component names, folders, ownership, or execution targets.
#
# Section 08 - Start/end time, logging, and reporting
#   This script records start time, end time, duration, status, JSONL audit
#   events, generated artifact checksums, artifact manifest, signing status, and
#   a final report location.
# ==============================================================================
# ------------------------------------------------------------------------------
# Step Descriptions
# ------------------------------------------------------------------------------
# | Step | Description | Explanation |
# |------|-------------|-------------|
# | 01   | Parse CLI | Reads project name, target, runtime, output root, image, dry-run, and quiet options. |
# | 02   | Validate CLI | Ensures project, target, runtime, component catalog, and B001 project state are valid. |
# | 03   | Resolve paths | Converts output root to an absolute path and computes project/runtime/evidence paths. |
# | 04   | Verify B001 foundation | Checks for B001 foundation evidence so B002 is tied to the approved substrate. |
# | 05   | Create runtime directories | Creates runtime component, contract, policy, test, observability, validation, and evidence folders. |
# | 06   | Write implementation skeletons | Writes concrete service/module skeletons, manifests, tests, contracts, and policies. |
# | 07   | Write task-specific artifacts | Writes domain-specific runtime artifacts for this B002 task. |
# | 08   | Write catalogs | Writes canonical YAML and JSON implementation catalogs. |
# | 09   | Write report and audit | Records runtime implementation evidence in Markdown and JSONL. |
# | 10   | Write integrity artifacts | Writes checksums, artifact manifest, and signing status. |
# ------------------------------------------------------------------------------

SCRIPT_ID="@SCRIPT_ID@"
SCRIPT_NAME="@SCRIPT_NAME@"
SCRIPT_VERSION="0.1.0"
SCRIPT_TITLE="@TITLE@"
SCRIPT_SUMMARY="@SUMMARY@"
PHASE="@PHASE@"
DOMAIN="@DOMAIN@"
WORKFLOW_STEP="@WORKFLOW@"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
EXECUTION_TARGET="${EXECUTION_TARGET:-auto}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
OUTPUT_ROOT="${OUTPUT_ROOT:-.}"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
DRY_RUN="no"
QUIET="no"
RUN_ID="${RUN_ID:-${SCRIPT_ID}_$(date -u +%Y%m%dT%H%M%SZ)_$$}"
SCRIPT_STARTED_AT="$(now_utc)"
SCRIPT_STARTED_EPOCH="$(now_epoch)"
PROJECT_ROOT=""
RUNTIME_ROOT=""
EVIDENCE_DIR=""
AUDIT_LOG=""
REPORT_PATH=""
RUN_STATE_PATH=""
CHECKSUMS_PATH=""
MANIFEST_PATH=""
SIGNING_STATUS=""
FINAL_STATUS="not_started"
COMPONENT_ROOT="@ROOT@"
EVIDENCE_NAME="@EVIDENCE_NAME@"
COMPONENTS=(
@COMPONENT_LINES@
)

usage() {
  cat <<EOF
BioDiscoveryAI ${SCRIPT_ID} ${SCRIPT_TITLE}

Usage:
  @FILE_NAME@ [options]

Options:
  --project-name NAME           Project directory name. Default: biodiscoveryai
  --target TARGET               auto, local, hpc, aws. Default: auto
  --container-runtime RUNTIME   auto, docker, apptainer, none. Default: auto
  --output-root PATH            Absolute or resolvable parent directory for project root. Default: current directory
  --image REF                   Container image reference for metadata
  --dry-run                     Print decisions but do not write artifacts
  --quiet                       Reduce informational logging
  -h, --help                    Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-name) PROJECT_NAME="${2:-}"; shift 2 ;;
      --target) EXECUTION_TARGET="${2:-}"; shift 2 ;;
      --container-runtime) CONTAINER_RUNTIME="${2:-}"; shift 2 ;;
      --output-root) OUTPUT_ROOT="${2:-}"; shift 2 ;;
      --image) IMAGE_REF="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN="yes"; shift ;;
      --quiet) QUIET="yes"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown argument: $1" ;;
    esac
  done
}

validate_cli() {
  [[ -n "${PROJECT_NAME}" ]] || fail "Project name cannot be empty."
  case "${EXECUTION_TARGET}" in auto|local|hpc|aws) ;; *) fail "Invalid target: ${EXECUTION_TARGET}" ;; esac
  case "${CONTAINER_RUNTIME}" in auto|docker|apptainer|none) ;; *) fail "Invalid container runtime: ${CONTAINER_RUNTIME}" ;; esac
  [[ "${#COMPONENTS[@]}" -gt 0 ]] || fail "Component catalog cannot be empty."
}

resolve_paths() {
  OUTPUT_ROOT="$(foundation_absolute_dir "${OUTPUT_ROOT}")"
  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"
  RUNTIME_ROOT="${PROJECT_ROOT}/${COMPONENT_ROOT}"
  EVIDENCE_DIR="${PROJECT_ROOT}/.runtime/${EVIDENCE_NAME}"
  AUDIT_LOG="${EVIDENCE_DIR}/audit.jsonl"
  REPORT_PATH="${EVIDENCE_DIR}/report.md"
  RUN_STATE_PATH="${EVIDENCE_DIR}/run_state.env"
  CHECKSUMS_PATH="${EVIDENCE_DIR}/checksums.txt"
  MANIFEST_PATH="${EVIDENCE_DIR}/manifest.jsonl"
  SIGNING_STATUS="${EVIDENCE_DIR}/signing_status.md"
}

write_audit() {
  local event="$1" status="$2" message="$3"
  foundation_write_jsonl "${AUDIT_LOG}" "${event}" "${status}" "run_id=${RUN_ID} ${message}"
}

verify_b001_foundation() {
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi
  mkdir -p "${EVIDENCE_DIR}"
  if [[ -d "${PROJECT_ROOT}/.foundation" ]]; then
    write_audit "${SCRIPT_ID}.b001_foundation" "found" "path=${PROJECT_ROOT}/.foundation"
  else
    write_audit "${SCRIPT_ID}.b001_foundation" "warning" "B001 .foundation directory not found; creating B002 artifacts anyway"
    warn "B001 .foundation directory not found under ${PROJECT_ROOT}; continuing so this task can be staged."
  fi
}

create_runtime_directories() {
  if [[ "${DRY_RUN}" == "yes" ]]; then
    info "DRY RUN: would create ${SCRIPT_TITLE} runtime directories under ${RUNTIME_ROOT}"
    return 0
  fi
  mkdir -p "${EVIDENCE_DIR}" "${RUNTIME_ROOT}"
  local component label purpose kind
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose kind <<< "${component}"
    mkdir -p \
      "${RUNTIME_ROOT}/${label}/src" \
      "${RUNTIME_ROOT}/${label}/contracts" \
      "${RUNTIME_ROOT}/${label}/policies" \
      "${RUNTIME_ROOT}/${label}/tests" \
      "${RUNTIME_ROOT}/${label}/observability" \
      "${RUNTIME_ROOT}/${label}/validation" \
      "${RUNTIME_ROOT}/${label}/evidence" \
      "${RUNTIME_ROOT}/${label}/runtime"
  done
}

write_component_skeletons() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local component label purpose kind module_name
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose kind <<< "${component}"
    module_name="${label//-/_}"
    cat > "${RUNTIME_ROOT}/${label}/component.yaml" <<EOF
component: ${label}
kind: ${kind}
phase: ${PHASE}
domain: ${DOMAIN}
workflow_step: ${WORKFLOW_STEP}
purpose: ${purpose}
status: implemented-skeleton
run_id: ${RUN_ID}
target: ${EXECUTION_TARGET}
container_runtime: ${CONTAINER_RUNTIME}
image_ref: ${IMAGE_REF}
interfaces:
  health: src/app.py
  contract: contracts/openapi.yaml
  policy: policies/runtime_policy.rego
  tests: tests/test_health.py
  observability: observability/metrics.md
controls:
  audit_required: true
  policy_required: true
  validation_required: true
  evidence_required: true
EOF
    cat > "${RUNTIME_ROOT}/${label}/README.md" <<EOF
# ${label}

Phase: ${PHASE}  
Domain: ${DOMAIN}  
Workflow step: ${WORKFLOW_STEP}  
Kind: ${kind}  
Purpose: ${purpose}

This B002 component is a concrete runtime skeleton. It is intentionally small,
auditable, container-friendly, and portable across local, HPC/Apptainer, and
AWS/Docker execution.
EOF
    cat > "${RUNTIME_ROOT}/${label}/src/app.py" <<EOF
from fastapi import FastAPI

app = FastAPI(title="${label}", version="${SCRIPT_VERSION}")


@app.get("/health")
def health():
    return {
        "component": "${label}",
        "phase": "${PHASE}",
        "domain": "${DOMAIN}",
        "status": "ok",
    }


@app.get("/runtime-contract")
def runtime_contract():
    return {
        "component": "${label}",
        "kind": "${kind}",
        "policy_required": True,
        "audit_required": True,
        "validation_required": True,
    }
EOF
    cat > "${RUNTIME_ROOT}/${label}/src/__init__.py" <<EOF
"""${label} runtime package."""
EOF
    cat > "${RUNTIME_ROOT}/${label}/tests/test_health.py" <<EOF
from src.app import health


def test_health_status_ok():
    assert health()["status"] == "ok"
EOF
    cat > "${RUNTIME_ROOT}/${label}/contracts/openapi.yaml" <<EOF
openapi: 3.1.0
info:
  title: ${label}
  version: ${SCRIPT_VERSION}
paths:
  /health:
    get:
      summary: Health check
      responses:
        "200":
          description: Component is healthy
  /runtime-contract:
    get:
      summary: Runtime contract
      responses:
        "200":
          description: Component runtime contract
EOF
    cat > "${RUNTIME_ROOT}/${label}/policies/runtime_policy.rego" <<EOF
package biodiscovery.${module_name}

default allow := false

allow if {
  input.action == "health"
}
EOF
    cat > "${RUNTIME_ROOT}/${label}/observability/metrics.md" <<EOF
# Observability: ${label}

| Signal | Required |
|--------|----------|
| health_status | yes |
| request_count | yes |
| error_count | yes |
| latency_ms | yes |
| audit_event_count | yes |
EOF
    cat > "${RUNTIME_ROOT}/${label}/validation/acceptance.md" <<EOF
# Validation Acceptance: ${label}

| Requirement | Evidence |
|-------------|----------|
| Health endpoint exists | tests/test_health.py |
| Contract placeholder exists | contracts/openapi.yaml |
| Runtime policy exists | policies/runtime_policy.rego |
| Audit hook required | component.yaml |
EOF
    cat > "${RUNTIME_ROOT}/${label}/runtime/run_local.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
uvicorn src.app:app --host 0.0.0.0 --port "\${PORT:-8000}"
EOF
    chmod +x "${RUNTIME_ROOT}/${label}/runtime/run_local.sh" 2>/dev/null || true
  done
}

write_task_specific_artifacts() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  case "${SCRIPT_ID}" in
    b002_01)
      mkdir -p "${PROJECT_ROOT}/runtime/contracts"
      cat > "${PROJECT_ROOT}/runtime/contracts/service-runtime-conventions.yaml" <<'EOF'
runtime_contract:
  health_endpoint: /health
  policy_required: true
  audit_required: true
  validation_required: true
  observability_required: true
  container_port_env: PORT
EOF
      ;;
    b002_02)
      mkdir -p "${PROJECT_ROOT}/tools/service-factory/templates/fastapi-service"
      cat > "${PROJECT_ROOT}/tools/service-factory/templates/fastapi-service/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir fastapi uvicorn
CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
      cat > "${PROJECT_ROOT}/tools/service-factory/generate_service.py" <<'EOF'
#!/usr/bin/env python3
"""Minimal service generator placeholder for B002 runtime services."""
from pathlib import Path
import sys

name = sys.argv[1] if len(sys.argv) > 1 else "new-service"
root = Path("apps") / name
(root / "src").mkdir(parents=True, exist_ok=True)
(root / "tests").mkdir(parents=True, exist_ok=True)
(root / "src" / "app.py").write_text("from fastapi import FastAPI\napp = FastAPI()\n", encoding="utf-8")
print(f"created {root}")
EOF
      chmod +x "${PROJECT_ROOT}/tools/service-factory/generate_service.py" 2>/dev/null || true
      ;;
    b002_07|b002_17)
      cat > "${PROJECT_ROOT}/docker-compose.runtime.yml" <<'EOF'
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: biodiscovery
    ports: ["5432:5432"]
  neo4j:
    image: neo4j:5
    environment:
      NEO4J_AUTH: neo4j/biodiscovery
    ports: ["7474:7474", "7687:7687"]
  opensearch:
    image: opensearchproject/opensearch:2
    environment:
      discovery.type: single-node
      plugins.security.disabled: "true"
    ports: ["9200:9200"]
EOF
      ;;
    b002_08)
      mkdir -p "${PROJECT_ROOT}/contracts/events"
      cat > "${PROJECT_ROOT}/contracts/events/event-envelope.schema.json" <<'EOF'
{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["event_id","event_type","occurred_at","payload"],"properties":{"event_id":{"type":"string"},"event_type":{"type":"string"},"occurred_at":{"type":"string"},"payload":{"type":"object"}}}
EOF
      ;;
    b002_18)
      mkdir -p "${PROJECT_ROOT}/infra/hpc" "${PROJECT_ROOT}/scripts/hpc"
      cat > "${PROJECT_ROOT}/infra/hpc/Apptainer.runtime.def" <<'EOF'
Bootstrap: docker
From: biodiscoveryai/foundation-runner:0.3.0

%post
    echo "B002 runtime Apptainer image placeholder"
EOF
      cat > "${PROJECT_ROOT}/scripts/hpc/run_b002_runtime.slurm" <<'EOF'
#!/bin/bash
#SBATCH --job-name=bdai-b002-runtime
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
apptainer exec runtime.sif bash -lc 'echo B002 runtime ready'
EOF
      ;;
    b002_19)
      mkdir -p "${PROJECT_ROOT}/infra/aws"
      cat > "${PROJECT_ROOT}/infra/aws/runtime-deployment-conventions.md" <<'EOF'
# AWS Runtime Deployment Conventions

Use ECR for images, ECS/EKS/Batch for execution, IAM least privilege, KMS
encryption, CloudWatch logs, and VPC egress controls before regulated data use.
EOF
      ;;
    b002_20)
      mkdir -p "${PROJECT_ROOT}/.github/workflows"
      cat > "${PROJECT_ROOT}/.github/workflows/b002-runtime-ci.yml" <<'EOF'
name: b002-runtime-ci
on:
  pull_request:
  push:
    branches: [main]
jobs:
  runtime-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: python -m compileall .
EOF
      ;;
    b002_21)
      mkdir -p "${PROJECT_ROOT}/security/scans"
      cat > "${PROJECT_ROOT}/security/scans/run_devsecops_scans.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
command -v gitleaks >/dev/null 2>&1 && gitleaks detect --source . --redact || true
command -v semgrep >/dev/null 2>&1 && semgrep scan --config auto || true
command -v trivy >/dev/null 2>&1 && trivy fs . || true
command -v grype >/dev/null 2>&1 && grype dir:. || true
command -v syft >/dev/null 2>&1 && syft dir:. -o spdx-json > sbom.spdx.json || true
command -v checkov >/dev/null 2>&1 && checkov -d . || true
command -v hadolint >/dev/null 2>&1 && find . -name Dockerfile -print0 | xargs -0 -r hadolint || true
EOF
      chmod +x "${PROJECT_ROOT}/security/scans/run_devsecops_scans.sh" 2>/dev/null || true
      ;;
  esac
}

write_catalogs() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local yaml_path="${EVIDENCE_DIR}/catalog.yaml"
  local json_path="${EVIDENCE_DIR}/catalog.json"
  cat > "${yaml_path}" <<EOF
script_id: ${SCRIPT_ID}
script_name: ${SCRIPT_NAME}
script_version: ${SCRIPT_VERSION}
phase: ${PHASE}
domain: ${DOMAIN}
workflow_step: ${WORKFLOW_STEP}
run_id: ${RUN_ID}
target: ${EXECUTION_TARGET}
container_runtime: ${CONTAINER_RUNTIME}
component_root: ${COMPONENT_ROOT}
components:
EOF
  local component label purpose kind
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose kind <<< "${component}"
    cat >> "${yaml_path}" <<EOF
  - name: ${label}
    kind: ${kind}
    purpose: ${purpose}
    manifest: ${COMPONENT_ROOT}/${label}/component.yaml
EOF
  done

  cat > "${json_path}" <<EOF
{
  "script_id": "$(json_escape "${SCRIPT_ID}")",
  "script_name": "$(json_escape "${SCRIPT_NAME}")",
  "script_version": "$(json_escape "${SCRIPT_VERSION}")",
  "phase": "$(json_escape "${PHASE}")",
  "domain": "$(json_escape "${DOMAIN}")",
  "workflow_step": "$(json_escape "${WORKFLOW_STEP}")",
  "run_id": "$(json_escape "${RUN_ID}")",
  "target": "$(json_escape "${EXECUTION_TARGET}")",
  "container_runtime": "$(json_escape "${CONTAINER_RUNTIME}")",
  "component_root": "$(json_escape "${COMPONENT_ROOT}")",
  "components": [
EOF
  local first="yes"
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose kind <<< "${component}"
    if [[ "${first}" == "yes" ]]; then first="no"; else printf ',\n' >> "${json_path}"; fi
    printf '    {"name":"%s","kind":"%s","purpose":"%s","manifest":"%s"}' \
      "$(json_escape "${label}")" \
      "$(json_escape "${kind}")" \
      "$(json_escape "${purpose}")" \
      "$(json_escape "${COMPONENT_ROOT}/${label}/component.yaml")" >> "${json_path}"
  done
  cat >> "${json_path}" <<EOF

  ]
}
EOF
}

write_run_state() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local ended_at ended_epoch duration
  ended_at="$(now_utc)"
  ended_epoch="$(now_epoch)"
  duration="$((ended_epoch - SCRIPT_STARTED_EPOCH))"
  cat > "${RUN_STATE_PATH}" <<EOF
RUN_ID=${RUN_ID}
SCRIPT_ID=${SCRIPT_ID}
SCRIPT_NAME=${SCRIPT_NAME}
SCRIPT_VERSION=${SCRIPT_VERSION}
PROJECT_NAME=${PROJECT_NAME}
PROJECT_ROOT=${PROJECT_ROOT}
RUNTIME_ROOT=${RUNTIME_ROOT}
EVIDENCE_DIR=${EVIDENCE_DIR}
EXECUTION_TARGET=${EXECUTION_TARGET}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME}
IMAGE_REF=${IMAGE_REF}
STARTED_AT=${SCRIPT_STARTED_AT}
ENDED_AT=${ended_at}
DURATION_SECONDS=${duration}
FINAL_STATUS=success
REPORT_PATH=${REPORT_PATH}
EOF
}

write_report() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local ended_at ended_epoch duration
  ended_at="$(now_utc)"
  ended_epoch="$(now_epoch)"
  duration="$((ended_epoch - SCRIPT_STARTED_EPOCH))"
  cat > "${REPORT_PATH}" <<EOF
# ${SCRIPT_ID} ${SCRIPT_TITLE} Execution Report

| Field | Value |
|-------|-------|
| Script | ${SCRIPT_NAME} |
| Version | ${SCRIPT_VERSION} |
| Phase | ${PHASE} |
| Domain | ${DOMAIN} |
| Workflow step | ${WORKFLOW_STEP} |
| Run ID | ${RUN_ID} |
| Target | ${EXECUTION_TARGET} |
| Container runtime | ${CONTAINER_RUNTIME} |
| Image | ${IMAGE_REF} |
| Project root | ${PROJECT_ROOT} |
| Runtime root | ${RUNTIME_ROOT} |
| Started at | ${SCRIPT_STARTED_AT} |
| Ended at | ${ended_at} |
| Duration seconds | ${duration} |
| Status | success |

## Components

| Component | Kind | Purpose | Manifest |
|-----------|------|---------|----------|
EOF
  local component label purpose kind
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose kind <<< "${component}"
    cat >> "${REPORT_PATH}" <<EOF
| ${label} | ${kind} | ${purpose} | ${COMPONENT_ROOT}/${label}/component.yaml |
EOF
  done
  cat >> "${REPORT_PATH}" <<EOF

## Portability Contract

Downstream scripts should consume catalog.yaml, catalog.json, run_state.env, and
component.yaml files from this run. This preserves portability across local,
HPC/Apptainer, and AWS/Docker execution.
EOF
}

write_integrity_artifacts() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  : > "${CHECKSUMS_PATH}"
  : > "${MANIFEST_PATH}"
  local path hash
  while IFS= read -r path; do
    [[ -f "${path}" ]] || continue
    hash="$(foundation_hash_file "${path}")"
    printf '%s  %s\n' "${hash}" "${path}" >> "${CHECKSUMS_PATH}"
    printf '{"run_id":"%s","artifact":"%s","sha256":"%s","purpose":"%s","importance":10}\n' \
      "$(json_escape "${RUN_ID}")" \
      "$(json_escape "${path}")" \
      "$(json_escape "${hash}")" \
      "$(json_escape "${SCRIPT_TITLE} runtime artifact")" >> "${MANIFEST_PATH}"
  done < <(find "${RUNTIME_ROOT}" "${EVIDENCE_DIR}" -type f ! -name 'checksums.txt' ! -name 'manifest.jsonl' ! -name 'signing_status.md' | sort)
}

sign_integrity_artifacts() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  cat > "${SIGNING_STATUS}" <<EOF
# Signing Status

| Artifact | Status | Tool |
|----------|--------|------|
EOF
  local artifact tool status
  for artifact in "${CHECKSUMS_PATH}" "${REPORT_PATH}" "${MANIFEST_PATH}"; do
    tool="none"
    status="unsigned-tool-unavailable"
    if command -v cosign >/dev/null 2>&1; then
      cosign sign-blob --yes "${artifact}" --output-signature "${artifact}.sig" >/dev/null 2>&1 && tool="cosign" && status="signed" || status="cosign-failed"
    elif command -v gpg >/dev/null 2>&1; then
      gpg --batch --yes --armor --detach-sign "${artifact}" >/dev/null 2>&1 && tool="gpg" && status="signed" || status="gpg-failed"
    fi
    printf '| %s | %s | %s |\n' "${artifact}" "${status}" "${tool}" >> "${SIGNING_STATUS}"
  done
}

finish_success() {
  FINAL_STATUS="success"
  write_audit "${SCRIPT_ID}.complete" "success" "report=${REPORT_PATH}"
  info "${SCRIPT_TITLE} runtime task complete. Report: ${REPORT_PATH}"
  printf 'Final report: %s\n' "${REPORT_PATH}"
}

on_error() {
  local line="$1" code="$2"
  FINAL_STATUS="failure"
  if [[ -n "${AUDIT_LOG}" && -d "$(dirname "${AUDIT_LOG}")" ]]; then
    write_audit "${SCRIPT_ID}.failure" "failure" "line=${line} exit=${code}"
  fi
  warn "${SCRIPT_TITLE} failed at line ${line} with exit code ${code}."
  [[ -n "${REPORT_PATH}" ]] && warn "Report path: ${REPORT_PATH}"
}
trap 'on_error ${LINENO} $?' ERR

main() {
  parse_args "$@"
  validate_cli
  resolve_paths
  create_runtime_directories
  if [[ "${DRY_RUN}" == "yes" ]]; then
    info "DRY RUN complete for ${SCRIPT_TITLE}. No artifacts written."
    return 0
  fi
  write_audit "${SCRIPT_ID}.start" "started" "phase=${PHASE} domain=${DOMAIN} workflow=${WORKFLOW_STEP}"
  verify_b001_foundation
  write_component_skeletons
  write_task_specific_artifacts
  write_catalogs
  write_run_state
  write_report
  write_integrity_artifacts
  sign_integrity_artifacts
  finish_success
}

main "$@"
