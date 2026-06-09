#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/foundation_common.sh"
# ==============================================================================
# Developer Documentation Index for @FILE_NAME@
# ==============================================================================
#
# Section 01 - Design principles
#   Explains the SOLID-style architecture decisions used by this script family.
#   Single Responsibility keeps this script focused on @TITLE@ only. Open/Closed
#   behavior allows new components to be added through the component catalog
#   without rewriting existing scaffolds. Liskov-style substitution means every
#   component exposes the same baseline contract: owner, purpose, interface lane,
#   governance hook, audit hook, validation hook, and observability hook.
#   Interface segregation keeps documentation, manifests, contracts, and reports
#   small. Dependency inversion keeps downstream scripts dependent on generated
#   manifests instead of hard-coded folders.
#
# Section 02 - What this script does
#   @SUMMARY@
#   Workflow step: @WORKFLOW@.
#
# Section 03 - How To Run On HPC
#   Use this on HPC to create this scaffold on approved project storage. Runtime
#   containers can later be built or executed with Apptainer/Singularity.
#
#   Direct execution:
#     chmod +x /path/to/@FILE_NAME@
#     /path/to/@FILE_NAME@ --project-name biodiscoveryai --target hpc --container-runtime apptainer
#
#   Slurm pattern:
#     sbatch <<'SLURM_EOF'
#     #!/bin/bash
#     #SBATCH --job-name=@SCRIPT_ID@
#     #SBATCH --time=00:05:00
#     #SBATCH --cpus-per-task=1
#     #SBATCH --mem=1G
#     /path/to/@FILE_NAME@ --project-name biodiscoveryai --target hpc --container-runtime apptainer
#     SLURM_EOF
#
# Section 04 - How To Run On AWS Cloud
#   Use this on AWS before Docker/ECR/ECS/EKS or AWS Batch deployment scripts
#   materialize runtime images and infrastructure.
#
#   Basic execution:
#     chmod +x /path/to/@FILE_NAME@
#     /path/to/@FILE_NAME@ --project-name biodiscoveryai --target aws --container-runtime docker
#
#   ECR image pattern:
#     /path/to/@FILE_NAME@ \
#       --project-name biodiscoveryai \
#       --target aws \
#       --container-runtime docker \
#       --image <aws_account_id>.dkr.ecr.<region>.amazonaws.com/biodiscoveryai/foundation-runner:0.3.0
#
# Section 05 - What It Does
#
# | Area                   | Capability                                                                                                      |
# |------------------------|-----------------------------------------------------------------------------------------------------------------|
# | Domain focus           | Creates the @TITLE@ scaffold and machine-readable domain catalog.                                                |
# | Workflow step          | Supports @WORKFLOW@.                                                                                            |
# | Component boundaries   | Creates one component lane per catalog entry with manifest, README, policy, contract, test, and evidence paths. |
# | Governance readiness   | Adds ownership, policy, audit, validation, risk, and observability placeholders for every component.             |
# | Contract readiness     | Creates component contract placeholders and a central catalog for downstream validators.                         |
# | Reporting              | Produces a human-readable Markdown execution report with start/end/duration/status.                              |
# | Auditability           | Produces JSONL audit events, checksums, artifact manifest, and optional signatures where tools are available.    |
# | Downstream integration | Generates catalog YAML/JSON artifacts that later scripts can source, parse, validate, or deploy.                 |
#
# Section 06 - Artifacts Created When The Script Runs
#
# | Artifact name                                       | Purpose                                      | Dependency               | Importance score |
# |-----------------------------------------------------|----------------------------------------------|--------------------------|-----------------:|
# | <project>/@ROOT@/<component>/README.md              | Human-readable component boundary            | mkdir, cat, date         |               10 |
# | <project>/@ROOT@/<component>/component.yaml          | Machine-readable component manifest          | mkdir, cat, date         |               10 |
# | <project>/@ROOT@/<component>/contracts/contract.md   | Contract placeholder                         | cat                      |                9 |
# | <project>/@ROOT@/<component>/tests/.keep             | Test lane marker                             | mkdir                    |                6 |
# | <project>/.foundation/@EVIDENCE_NAME@/catalog.yaml   | Central domain catalog                       | cat                      |               10 |
# | <project>/.foundation/@EVIDENCE_NAME@/catalog.json   | Machine-readable domain catalog              | cat                      |               10 |
# | <project>/.foundation/@EVIDENCE_NAME@/report.md      | Markdown execution report                    | date, cat                |               10 |
# | <project>/.foundation/@EVIDENCE_NAME@/audit.jsonl    | JSONL execution audit trail                  | date, sed                |               10 |
# | <project>/.foundation/@EVIDENCE_NAME@/checksums.txt  | SHA-256 checksums for generated files        | sha256sum/shasum/openssl |               10 |
# | <project>/.foundation/@EVIDENCE_NAME@/manifest.jsonl | Canonical artifact manifest                  | sha256sum/shasum/openssl |               10 |
#
# Section 07 - Portability contract
#   Downstream scripts should read .foundation/@EVIDENCE_NAME@/catalog.yaml,
#   .foundation/@EVIDENCE_NAME@/catalog.json, and each component.yaml instead of
#   hard-coding component names, folders, ownership, or workflow assumptions.
#
# Section 08 - Start/end time, logging, and reporting
#   This script records start time, end time, duration, status, JSONL audit
#   events, generated artifact checksums, artifact manifest, and a Markdown report.
# ==============================================================================
# ------------------------------------------------------------------------------
# Step Descriptions
# ------------------------------------------------------------------------------
# | Step | Description | Explanation |
# |------|-------------|-------------|
# | 01   | Parse CLI | Reads project name, target, runtime, output root, image, dry-run, and quiet options. |
# | 02   | Validate CLI | Ensures project, target, runtime, and component catalog values are valid. |
# | 03   | Resolve paths | Computes project root, domain root, and evidence paths. |
# | 04   | Create component directories | Creates component lanes, contracts, policies, tests, observability, validation, and evidence directories. |
# | 05   | Write component manifests | Writes per-component YAML manifests and README files. |
# | 06   | Write contract placeholders | Writes per-component contract placeholders for later contract-first implementation. |
# | 07   | Write central catalogs | Writes canonical YAML and JSON catalogs for this domain. |
# | 08   | Write report and audit | Records scaffold evidence in Markdown and JSONL. |
# | 09   | Write integrity artifacts | Writes checksums and artifact manifest for generated files. |
# | 10   | Sign integrity artifacts where possible | Signs key integrity artifacts with cosign or GPG when available; otherwise records unsigned status. |
# ------------------------------------------------------------------------------

SCRIPT_ID="@SCRIPT_ID@"
SCRIPT_NAME="@SCRIPT_NAME@"
SCRIPT_VERSION="0.1.0"
SCRIPT_TITLE="@TITLE@"
SCRIPT_SUMMARY="@SUMMARY@"
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
DOMAIN_ROOT=""
EVIDENCE_DIR=""
AUDIT_LOG=""
REPORT_PATH=""
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
  --output-root PATH            Parent directory for project root. Default: current directory
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
  DOMAIN_ROOT="${PROJECT_ROOT}/${COMPONENT_ROOT}"
  EVIDENCE_DIR="${PROJECT_ROOT}/.foundation/${EVIDENCE_NAME}"
  AUDIT_LOG="${EVIDENCE_DIR}/audit.jsonl"
  REPORT_PATH="${EVIDENCE_DIR}/report.md"
  CHECKSUMS_PATH="${EVIDENCE_DIR}/checksums.txt"
  MANIFEST_PATH="${EVIDENCE_DIR}/manifest.jsonl"
  SIGNING_STATUS="${EVIDENCE_DIR}/signing_status.md"
}

write_audit() {
  local event="$1" status="$2" message="$3"
  foundation_write_jsonl "${AUDIT_LOG}" "${event}" "${status}" "run_id=${RUN_ID} ${message}"
}

create_component_directories() {
  if [[ "${DRY_RUN}" == "yes" ]]; then
    info "DRY RUN: would create ${SCRIPT_TITLE} component directories under ${DOMAIN_ROOT}"
    return 0
  fi
  mkdir -p "${EVIDENCE_DIR}" "${DOMAIN_ROOT}"
  local component label purpose
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose <<< "${component}"
    mkdir -p \
      "${DOMAIN_ROOT}/${label}/contracts" \
      "${DOMAIN_ROOT}/${label}/policies" \
      "${DOMAIN_ROOT}/${label}/tests" \
      "${DOMAIN_ROOT}/${label}/observability" \
      "${DOMAIN_ROOT}/${label}/validation" \
      "${DOMAIN_ROOT}/${label}/evidence"
    touch "${DOMAIN_ROOT}/${label}/tests/.keep" "${DOMAIN_ROOT}/${label}/evidence/.keep"
  done
}

write_component_manifests() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local component label purpose
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose <<< "${component}"
    cat > "${DOMAIN_ROOT}/${label}/component.yaml" <<EOF
component: ${label}
title: ${label}
domain: ${SCRIPT_TITLE}
workflow_step: ${WORKFLOW_STEP}
purpose: ${purpose}
owner: TBD
status: scaffolded
run_id: ${RUN_ID}
target: ${EXECUTION_TARGET}
container_runtime: ${CONTAINER_RUNTIME}
image_ref: ${IMAGE_REF}
interfaces:
  contract: contracts/contract.md
  policy: policies/policy.md
  observability: observability/README.md
  validation: validation/README.md
controls:
  audit_required: true
  policy_required: true
  validation_required: true
  evidence_required: true
EOF
    cat > "${DOMAIN_ROOT}/${label}/README.md" <<EOF
# ${label}

Domain: ${SCRIPT_TITLE}  
Workflow step: ${WORKFLOW_STEP}  
Purpose: ${purpose}

## Boundary

This component is scaffolded as a stable extension boundary. Downstream build,
validation, deployment, and governance scripts should consume component.yaml
rather than hard-coding paths or assumptions.

## Required lanes

| Lane | Purpose | Status |
|------|---------|--------|
| contracts | Contract-first interface definition | placeholder |
| policies | Governance and security policy hooks | placeholder |
| tests | Unit, contract, and validation tests | placeholder |
| observability | Metrics, traces, logs, and dashboards | placeholder |
| validation | Assurance evidence and acceptance checks | placeholder |
| evidence | Audit and compliance evidence | placeholder |
EOF
  done
}

write_contract_placeholders() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local component label purpose
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose <<< "${component}"
    cat > "${DOMAIN_ROOT}/${label}/contracts/contract.md" <<EOF
# Contract Placeholder: ${label}

Purpose: ${purpose}

Required future content:

| Contract area | Requirement |
|---------------|-------------|
| Inputs | Define accepted request, event, file, or data inputs. |
| Outputs | Define produced responses, events, files, evidence, or state changes. |
| Errors | Define recoverable and terminal failure modes. |
| Audit | Define required audit events and retention class. |
| Policy | Define authorization, export, data boundary, and safety controls. |
| Validation | Define tests, evidence, and reviewer acceptance criteria. |
EOF
    cat > "${DOMAIN_ROOT}/${label}/policies/policy.md" <<EOF
# Policy Placeholder: ${label}

This placeholder records that ${label} requires explicit policy-as-code coverage
before production use.
EOF
    cat > "${DOMAIN_ROOT}/${label}/observability/README.md" <<EOF
# Observability Placeholder: ${label}

Define service/component health, metrics, traces, logs, dashboards, alerts, and
SLO/SLA signals here.
EOF
    cat > "${DOMAIN_ROOT}/${label}/validation/README.md" <<EOF
# Validation Placeholder: ${label}

Define acceptance tests, regression checks, evidence requirements, and validation
sign-off criteria here.
EOF
  done
}

write_catalogs() {
  [[ "${DRY_RUN}" == "yes" ]] && return 0
  local yaml_path="${EVIDENCE_DIR}/catalog.yaml"
  local json_path="${EVIDENCE_DIR}/catalog.json"
  cat > "${yaml_path}" <<EOF
script_id: ${SCRIPT_ID}
script_name: ${SCRIPT_NAME}
script_version: ${SCRIPT_VERSION}
title: ${SCRIPT_TITLE}
workflow_step: ${WORKFLOW_STEP}
run_id: ${RUN_ID}
target: ${EXECUTION_TARGET}
container_runtime: ${CONTAINER_RUNTIME}
component_root: ${COMPONENT_ROOT}
components:
EOF
  local component label purpose
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose <<< "${component}"
    cat >> "${yaml_path}" <<EOF
  - name: ${label}
    purpose: ${purpose}
    manifest: ${COMPONENT_ROOT}/${label}/component.yaml
    contract: ${COMPONENT_ROOT}/${label}/contracts/contract.md
EOF
  done

  cat > "${json_path}" <<EOF
{
  "script_id": "$(json_escape "${SCRIPT_ID}")",
  "script_name": "$(json_escape "${SCRIPT_NAME}")",
  "script_version": "$(json_escape "${SCRIPT_VERSION}")",
  "title": "$(json_escape "${SCRIPT_TITLE}")",
  "workflow_step": "$(json_escape "${WORKFLOW_STEP}")",
  "run_id": "$(json_escape "${RUN_ID}")",
  "target": "$(json_escape "${EXECUTION_TARGET}")",
  "container_runtime": "$(json_escape "${CONTAINER_RUNTIME}")",
  "component_root": "$(json_escape "${COMPONENT_ROOT}")",
  "components": [
EOF
  local first="yes"
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose <<< "${component}"
    if [[ "${first}" == "yes" ]]; then
      first="no"
    else
      printf ',\n' >> "${json_path}"
    fi
    printf '    {"name":"%s","purpose":"%s","manifest":"%s","contract":"%s"}' \
      "$(json_escape "${label}")" \
      "$(json_escape "${purpose}")" \
      "$(json_escape "${COMPONENT_ROOT}/${label}/component.yaml")" \
      "$(json_escape "${COMPONENT_ROOT}/${label}/contracts/contract.md")" >> "${json_path}"
  done
  cat >> "${json_path}" <<EOF

  ]
}
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
| Run ID | ${RUN_ID} |
| Workflow step | ${WORKFLOW_STEP} |
| Target | ${EXECUTION_TARGET} |
| Container runtime | ${CONTAINER_RUNTIME} |
| Image | ${IMAGE_REF} |
| Project root | ${PROJECT_ROOT} |
| Domain root | ${DOMAIN_ROOT} |
| Started at | ${SCRIPT_STARTED_AT} |
| Ended at | ${ended_at} |
| Duration seconds | ${duration} |
| Status | success |

## Components

| Component | Purpose | Manifest |
|-----------|---------|----------|
EOF
  local component label purpose
  for component in "${COMPONENTS[@]}"; do
    IFS='|' read -r label purpose <<< "${component}"
    cat >> "${REPORT_PATH}" <<EOF
| ${label} | ${purpose} | ${COMPONENT_ROOT}/${label}/component.yaml |
EOF
  done
  cat >> "${REPORT_PATH}" <<EOF

## Portability Contract

Downstream scripts should consume catalog.yaml, catalog.json, and component.yaml
files from this run. This preserves portability across local, HPC/Apptainer, and
AWS/Docker execution without rebuilding this scaffold from scratch.
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
      "$(json_escape "${SCRIPT_TITLE} scaffold artifact")" >> "${MANIFEST_PATH}"
  done < <(find "${DOMAIN_ROOT}" "${EVIDENCE_DIR}" -type f ! -name 'checksums.txt' ! -name 'manifest.jsonl' ! -name 'signing_status.md' | sort)
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
  info "${SCRIPT_TITLE} scaffold complete. Report: ${REPORT_PATH}"
}

on_error() {
  local line="$1" code="$2"
  FINAL_STATUS="failure"
  if [[ -n "${AUDIT_LOG}" && -d "$(dirname "${AUDIT_LOG}")" ]]; then
    write_audit "${SCRIPT_ID}.failure" "failure" "line=${line} exit=${code}"
  fi
  warn "${SCRIPT_TITLE} scaffold failed at line ${line} with exit code ${code}."
  [[ -n "${REPORT_PATH}" ]] && warn "Report path: ${REPORT_PATH}"
}
trap 'on_error ${LINENO} $?' ERR

main() {
  parse_args "$@"
  validate_cli
  resolve_paths
  create_component_directories
  if [[ "${DRY_RUN}" == "yes" ]]; then
    info "DRY RUN complete for ${SCRIPT_TITLE}. No artifacts written."
    return 0
  fi
  write_audit "${SCRIPT_ID}.start" "started" "title=${SCRIPT_TITLE} workflow=${WORKFLOW_STEP}"
  write_component_manifests
  write_contract_placeholders
  write_catalogs
  write_report
  write_integrity_artifacts
  sign_integrity_artifacts
  finish_success
}

main "$@"
