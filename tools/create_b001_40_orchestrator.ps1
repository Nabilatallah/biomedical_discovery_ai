$targetPath = 'C:\biodiscovery\01_foundation\b001_40_foundation_orchestrator.sh'
$content = @'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/foundation_common.sh"
# ==============================================================================
# Developer Documentation Index for b001_40_foundation_orchestrator.sh
# ==============================================================================
#
# Section 01 - Design principles
#   Explains the SOLID-style architecture decisions used by this script family.
#   Single Responsibility keeps this script focused on orchestration of the
#   foundation scripts only. It does not duplicate domain-scaffold logic.
#   Open/Closed behavior allows future b001 scripts to be added to the run list
#   without changing downstream project structure. Liskov-style substitution means
#   every child script is treated through the same execution contract: arguments,
#   start time, end time, duration, exit status, report location, and audit event.
#   Interface segregation keeps the orchestrator report separate from each child
#   script's domain report. Dependency inversion keeps this control plane
#   dependent on script files and generated artifacts, not on implementation
#   internals inside each domain script.
#
# Section 02 - What this script does
#   Runs the modular BioDiscoveryAI b001 foundation family in a controlled order.
#   By default it executes b001_01 through b001_39, stops on first failure, writes
#   a master JSONL audit log, writes a master Markdown report, records per-script
#   duration/status, writes checksums and an artifact manifest, and prints the
#   final report location. It preserves the existing CLI contract of child
#   scripts: b001_01 receives --output-dir, while b001_07 and later receive
#   --output-root.
#
# Section 03 - How To Run On HPC
#   Use this on HPC inside an approved Apptainer/Singularity foundation-runner
#   container, with the project output path mounted on approved scratch/project
#   storage.
#
#   Direct execution:
#     chmod +x /path/to/b001_40_foundation_orchestrator.sh
#     /path/to/b001_40_foundation_orchestrator.sh --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /approved/project/storage
#
#   Apptainer pattern:
#     apptainer exec \
#       --bind /approved/project/storage:/work \
#       foundation-runner.sif \
#       /foundation/b001_40_foundation_orchestrator.sh --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /work
#
#   Slurm pattern:
#     sbatch <<'SLURM_EOF'
#     #!/bin/bash
#     #SBATCH --job-name=bdai-foundation
#     #SBATCH --time=00:30:00
#     #SBATCH --cpus-per-task=2
#     #SBATCH --mem=4G
#     apptainer exec --bind /approved/project/storage:/work foundation-runner.sif \
#       /foundation/b001_40_foundation_orchestrator.sh --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /work
#     SLURM_EOF
#
# Section 04 - How To Run On AWS Cloud
#   Use this on AWS inside the same foundation-runner Docker image before ECS,
#   EKS, Batch, or CodeBuild jobs materialize specialized runtime infrastructure.
#
#   Docker pattern:
#     docker run --rm \
#       -v "$PWD/out:/work" \
#       -v "$PWD/01_foundation:/foundation:ro" \
#       biodiscoveryai/foundation-runner:0.3.0 \
#       /foundation/b001_40_foundation_orchestrator.sh --project-name biodiscoveryai --target aws --container-runtime docker --output-root /work
#
#   AWS CodeBuild/Batch pattern:
#     /foundation/b001_40_foundation_orchestrator.sh \
#       --project-name biodiscoveryai \
#       --target aws \
#       --container-runtime docker \
#       --output-root "$CODEBUILD_SRC_DIR/out" \
#       --image <aws_account_id>.dkr.ecr.<region>.amazonaws.com/biodiscoveryai/foundation-runner:0.3.0
#
# Section 05 - What It Does
#
# | Area                   | Capability                                                                                                     |
# |------------------------|----------------------------------------------------------------------------------------------------------------|
# | Domain focus           | Orchestrates the complete b001 modular foundation family.                                                       |
# | Workflow step          | Foundation control plane and master execution ledger.                                                           |
# | Execution order        | Runs b001_01 through b001_39 by default, with --from, --to, --only, and --skip controls.                        |
# | Runtime portability    | Passes target/runtime/image arguments through to child scripts for local, HPC/Apptainer, and AWS/Docker runs.   |
# | Failure behavior       | Stops on first failure by default, or continues when --continue-on-failure is supplied.                         |
# | Reporting              | Produces a master Markdown execution report with start/end/duration/status per child script.                    |
# | Auditability           | Produces JSONL audit events, checksums, artifact manifest, and optional signatures where tools are available.   |
# | Downstream integration | Generates a master execution catalog that CI, HPC schedulers, AWS jobs, and governance reviews can consume.     |
#
# Section 06 - Artifacts Created When The Script Runs
#
# | Artifact name                                                | Purpose                                      | Dependency               | Importance score |
# |--------------------------------------------------------------|----------------------------------------------|--------------------------|-----------------:|
# | <project>/.foundation/foundation_orchestrator/report.md       | Master Markdown execution report             | date, cat                |               10 |
# | <project>/.foundation/foundation_orchestrator/audit.jsonl     | Master JSONL execution audit trail           | date, sed                |               10 |
# | <project>/.foundation/foundation_orchestrator/run_state.env   | Shell-sourceable final orchestration state   | cat                      |                9 |
# | <project>/.foundation/foundation_orchestrator/run_catalog.tsv | Per-script status, timing, and exit ledger   | printf                   |               10 |
# | <project>/.foundation/foundation_orchestrator/checksums.txt   | SHA-256 checksums for orchestrator artifacts | sha256sum/shasum/openssl |               10 |
# | <project>/.foundation/foundation_orchestrator/manifest.jsonl  | Canonical artifact manifest                  | sha256sum/shasum/openssl |               10 |
# | <project>/.foundation/foundation_orchestrator/signing_status.md | Signature status for key integrity files   | cosign/gpg optional      |                8 |
#
# Section 07 - Portability contract
#   Downstream automation should read run_state.env, run_catalog.tsv, report.md,
#   and audit.jsonl to determine whether the foundation is complete. Child
#   scripts remain the source of truth for domain-specific outputs; this script is
#   the source of truth for full-family execution status.
#
# Section 08 - Start/end time, logging, and reporting
#   This script records start time, end time, duration, status, per-script JSONL
#   audit events, generated artifact checksums, an artifact manifest, and a final
#   report location. Trap-based failure reporting records the failing line and
#   current child script when an unhandled error occurs.
# ==============================================================================
# ------------------------------------------------------------------------------
# Step Descriptions
# ------------------------------------------------------------------------------
# | Step | Description | Explanation |
# |------|-------------|-------------|
# | 01   | Parse CLI | Reads project name, target, runtime, output root, image, selection, dry-run, and quiet options. |
# | 02   | Validate CLI | Ensures target/runtime values are valid and selected child scripts exist. |
# | 03   | Resolve paths | Computes project root and master orchestrator evidence paths. |
# | 04   | Initialize evidence | Creates orchestrator evidence directory and run ledgers. |
# | 05   | Build execution plan | Applies --from, --to, --only, --skip, and --include-common filters. |
# | 06   | Execute child scripts | Runs selected scripts in order with correct child CLI arguments. |
# | 07   | Capture child status | Records start/end/duration/exit code for every child script. |
# | 08   | Write master report | Produces the master Markdown report and final run state. |
# | 09   | Write integrity artifacts | Writes checksums and artifact manifest for orchestrator outputs. |
# | 10   | Sign integrity artifacts where possible | Signs key integrity artifacts with cosign or GPG when available; otherwise records unsigned status. |
# ------------------------------------------------------------------------------

SCRIPT_ID="b001_40"
SCRIPT_NAME="foundation-orchestrator"
SCRIPT_VERSION="0.1.0"
SCRIPT_TITLE="Foundation Orchestrator"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
EXECUTION_TARGET="${EXECUTION_TARGET:-auto}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
OUTPUT_ROOT="${OUTPUT_ROOT:-.}"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
FROM_STEP="01"
TO_STEP="39"
ONLY_LIST=""
SKIP_LIST=""
INCLUDE_COMMON="no"
CONTINUE_ON_FAILURE="no"
DRY_RUN="no"
QUIET="no"
RUN_ID="${RUN_ID:-${SCRIPT_ID}_$(date -u +%Y%m%dT%H%M%SZ)_$$}"
SCRIPT_STARTED_AT="$(now_utc)"
SCRIPT_STARTED_EPOCH="$(now_epoch)"
PROJECT_ROOT=""
EVIDENCE_DIR=""
AUDIT_LOG=""
REPORT_PATH=""
RUN_STATE_PATH=""
RUN_CATALOG_PATH=""
CHECKSUMS_PATH=""
MANIFEST_PATH=""
SIGNING_STATUS=""
CURRENT_CHILD_SCRIPT=""
FINAL_STATUS="not_started"
SELECTED_SCRIPTS=()

FOUNDATION_SCRIPTS=(
  "00|b001_00_foundation_common.sh|Foundation Common Framework|Shared helper framework setup"
  "01|b001_01_runtime_safety_preflight.sh|Runtime Safety Preflight|Bootstrap / preflight"
  "02|b001_02_aws_execution_preflight.sh|AWS Execution Preflight|AWS execution bootstrap"
  "03|b001_03_hpc_execution_preflight.sh|HPC Execution Preflight|HPC execution bootstrap"
  "04|b001_04_policy_governance_preflight.sh|Policy Governance Preflight|Policy governance preflight"
  "05|b001_05_contract_architecture_preflight.sh|Contract Architecture Preflight|Contract architecture preflight"
  "06|b001_06_hipaa_compliance_preflight.sh|HIPAA Compliance Preflight|HIPAA/ePHI governance preflight"
  "07|b001_07_project_initialization.sh|Project Initialization|Bootstrap / project creation"
  "08|b001_08_core_application_services.sh|Core Application Services|Service boundary setup"
  "09|b001_09_scientific_intelligence_services.sh|Scientific Intelligence Services|Scientific workflow scaffold"
  "10|b001_10_user_experience_layer.sh|User Experience Layer|Experience workflow scaffold"
  "11|b001_11_shared_platform_libraries.sh|Shared Platform Libraries|Shared SDK setup"
  "12|b001_12_enterprise_domain_layer.sh|Enterprise Domain Layer|Domain architecture setup"
  "13|b001_13_contracts_interfaces.sh|Contracts and Interfaces|Contract-first setup"
  "14|b001_14_data_foundation.sh|Data Foundation|Data foundation setup"
  "15|b001_15_data_integration_substrate.sh|Data and Integration Substrate|Data connector setup"
  "16|b001_16_integration_layer.sh|Integration Layer|External integration setup"
  "17|b001_17_orchestration_layer.sh|Orchestration Layer|Runtime orchestration setup"
  "18|b001_18_intelligence_layer.sh|Intelligence Layer|AI/science intelligence setup"
  "19|b001_19_governance_layer.sh|Governance Layer|Governance runtime setup"
  "20|b001_20_security_layer.sh|Security Layer|Security architecture setup"
  "21|b001_21_platform_infrastructure.sh|Platform Infrastructure|Infrastructure setup"
  "22|b001_22_runtime_persistence.sh|Runtime Persistence|Persistence setup"
  "23|b001_23_observability_reliability.sh|Observability and Reliability|Observability setup"
  "24|b001_24_validation_assurance.sh|Validation and Assurance|Validation setup"
  "25|b001_25_operations_layer.sh|Operations Layer|Operations setup"
  "26|b001_26_commercial_layer.sh|Commercial Layer|Commercial ops setup"
  "27|b001_27_frontier_future_science_layer.sh|Frontier Future Science Layer|Future science setup"
  "28|b001_28_registries.sh|Registries|Registry control-plane setup"
  "29|b001_29_plugin_architecture.sh|Plugin Architecture|Plugin substrate setup"
  "30|b001_30_extension_points.sh|Extension Points|Extension interface setup"
  "31|b001_31_documentation_governance_docs.sh|Documentation Governance Docs|Documentation generation"
  "32|b001_32_architecture_documentation.sh|Architecture Documentation|Architecture documentation"
  "33|b001_33_policy_as_code.sh|Policy-as-Code|Policy foundation setup"
  "34|b001_34_service_template_generator.sh|Service Template Generator|Service factory setup"
  "35|b001_35_developer_tooling.sh|Developer Tooling|Developer environment setup"
  "36|b001_36_cicd.sh|CI/CD|CI/CD setup"
  "37|b001_37_foundation_validation.sh|Foundation Validation|Validation execution"
  "38|b001_38_script_registry_reporting.sh|Script Registry Reporting|Build ledger / reporting"
  "39|b001_39_next_step_guidance.sh|Next-Step Guidance|Handoff / next-step guidance"
)

usage() {
  cat <<'EOF'
BioDiscoveryAI b001_40 Foundation Orchestrator

Usage:
  b001_40_foundation_orchestrator.sh [options]

Options:
  --project-name NAME           Project directory name. Default: biodiscoveryai
  --target TARGET               auto, local, hpc, aws. Default: auto
  --container-runtime RUNTIME   auto, docker, apptainer, none. Default: auto
  --output-root PATH            Parent directory for project root. Default: current directory
  --image REF                   Container image reference for child script metadata
  --from NN                     First script number to run. Default: 01
  --to NN                       Last script number to run. Default: 39
  --only LIST                   Comma-separated script numbers to run, such as 01,07,08
  --skip LIST                   Comma-separated script numbers to skip
  --include-common              Include b001_00 in the run plan
  --continue-on-failure         Continue after a child script failure
  --dry-run                     Print plan but do not execute child scripts
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
      --from) FROM_STEP="$(normalize_step "${2:-}")"; shift 2 ;;
      --to) TO_STEP="$(normalize_step "${2:-}")"; shift 2 ;;
      --only) ONLY_LIST="${2:-}"; shift 2 ;;
      --skip) SKIP_LIST="${2:-}"; shift 2 ;;
      --include-common) INCLUDE_COMMON="yes"; shift ;;
      --continue-on-failure) CONTINUE_ON_FAILURE="yes"; shift ;;
      --dry-run) DRY_RUN="yes"; shift ;;
      --quiet) QUIET="yes"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown argument: $1" ;;
    esac
  done
}

normalize_step() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || fail "Invalid step number: ${value}"
  printf '%02d' "${value#0}"
}

step_to_int() {
  local value="$1"
  printf '%d' "10#${value}"
}

csv_contains_step() {
  local csv="$1" step="$2"
  [[ -n "${csv}" ]] || return 1
  local item normalized
  IFS=',' read -r -a items <<< "${csv}"
  for item in "${items[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -n "${item}" ]] || continue
    normalized="$(normalize_step "${item}")"
    [[ "${normalized}" == "${step}" ]] && return 0
  done
  return 1
}

validate_cli() {
  [[ -n "${PROJECT_NAME}" ]] || fail "Project name cannot be empty."
  case "${EXECUTION_TARGET}" in auto|local|hpc|aws) ;; *) fail "Invalid target: ${EXECUTION_TARGET}" ;; esac
  case "${CONTAINER_RUNTIME}" in auto|docker|apptainer|none) ;; *) fail "Invalid container runtime: ${CONTAINER_RUNTIME}" ;; esac
  [[ "$(step_to_int "${FROM_STEP}")" -le "$(step_to_int "${TO_STEP}")" ]] || fail "--from must be less than or equal to --to."
}

resolve_paths() {
  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"
  EVIDENCE_DIR="${PROJECT_ROOT}/.foundation/foundation_orchestrator"
  AUDIT_LOG="${EVIDENCE_DIR}/audit.jsonl"
  REPORT_PATH="${EVIDENCE_DIR}/report.md"
  RUN_STATE_PATH="${EVIDENCE_DIR}/run_state.env"
  RUN_CATALOG_PATH="${EVIDENCE_DIR}/run_catalog.tsv"
  CHECKSUMS_PATH="${EVIDENCE_DIR}/checksums.txt"
  MANIFEST_PATH="${EVIDENCE_DIR}/manifest.jsonl"
  SIGNING_STATUS="${EVIDENCE_DIR}/signing_status.md"
}

write_audit() {
  local event="$1" status="$2" message="$3"
  foundation_write_jsonl "${AUDIT_LOG}" "${event}" "${status}" "run_id=${RUN_ID} ${message}"
}

initialize_evidence() {
  mkdir -p "${EVIDENCE_DIR}"
  : > "${AUDIT_LOG}"
  printf 'step\tscript\ttitle\tworkflow\tstatus\tstarted_at\tended_at\tduration_seconds\texit_code\n' > "${RUN_CATALOG_PATH}"
  write_audit "${SCRIPT_ID}.start" "started" "project=${PROJECT_NAME} target=${EXECUTION_TARGET} runtime=${CONTAINER_RUNTIME}"
}

build_execution_plan() {
  SELECTED_SCRIPTS=()
  local entry step script title workflow step_int from_int to_int
  from_int="$(step_to_int "${FROM_STEP}")"
  to_int="$(step_to_int "${TO_STEP}")"
  for entry in "${FOUNDATION_SCRIPTS[@]}"; do
    IFS='|' read -r step script title workflow <<< "${entry}"
    step_int="$(step_to_int "${step}")"
    [[ "${step}" == "00" && "${INCLUDE_COMMON}" != "yes" ]] && continue
    [[ -n "${ONLY_LIST}" ]] && ! csv_contains_step "${ONLY_LIST}" "${step}" && continue
    [[ -z "${ONLY_LIST}" && "${step_int}" -lt "${from_int}" ]] && continue
    [[ -z "${ONLY_LIST}" && "${step_int}" -gt "${to_int}" ]] && continue
    csv_contains_step "${SKIP_LIST}" "${step}" && continue
    [[ -f "${SCRIPT_DIR}/${script}" ]] || fail "Required child script not found: ${SCRIPT_DIR}/${script}"
    SELECTED_SCRIPTS+=("${entry}")
  done
  [[ "${#SELECTED_SCRIPTS[@]}" -gt 0 ]] || fail "No child scripts selected."
}

child_args_for_step() {
  local step="$1"
  local args=(
    "--project-name" "${PROJECT_NAME}"
    "--target" "${EXECUTION_TARGET}"
    "--container-runtime" "${CONTAINER_RUNTIME}"
  )
  if [[ "${step}" == "01" ]]; then
    args+=("--output-dir" "${PROJECT_ROOT}/.foundation/preflight")
  elif [[ "${step}" != "00" ]]; then
    args+=("--output-root" "${OUTPUT_ROOT}")
  fi
  if [[ "${step}" != "00" ]]; then
    args+=("--image" "${IMAGE_REF}")
  fi
  [[ "${QUIET}" == "yes" ]] && args+=("--quiet")
  printf '%s\n' "${args[@]}"
}

execute_child_script() {
  local entry="$1"
  local step script title workflow started_at started_epoch ended_at ended_epoch duration exit_code status
  IFS='|' read -r step script title workflow <<< "${entry}"
  CURRENT_CHILD_SCRIPT="${script}"
  started_at="$(now_utc)"
  started_epoch="$(now_epoch)"
  write_audit "${SCRIPT_ID}.child.start" "started" "step=${step} script=${script}"

  if [[ "${DRY_RUN}" == "yes" ]]; then
    info "DRY RUN: would run ${script}"
    ended_at="$(now_utc)"
    ended_epoch="$(now_epoch)"
    duration="$((ended_epoch - started_epoch))"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${step}" "${script}" "${title}" "${workflow}" "dry-run" "${started_at}" "${ended_at}" "${duration}" "0" >> "${RUN_CATALOG_PATH}"
    write_audit "${SCRIPT_ID}.child.dry_run" "dry-run" "step=${step} script=${script}"
    return 0
  fi

  mapfile -t child_args < <(child_args_for_step "${step}")
  if bash "${SCRIPT_DIR}/${script}" "${child_args[@]}"; then
    exit_code=0
    status="success"
  else
    exit_code=$?
    status="failure"
  fi

  ended_at="$(now_utc)"
  ended_epoch="$(now_epoch)"
  duration="$((ended_epoch - started_epoch))"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${step}" "${script}" "${title}" "${workflow}" "${status}" "${started_at}" "${ended_at}" "${duration}" "${exit_code}" >> "${RUN_CATALOG_PATH}"
  write_audit "${SCRIPT_ID}.child.complete" "${status}" "step=${step} script=${script} exit_code=${exit_code} duration=${duration}"
  CURRENT_CHILD_SCRIPT=""

  if [[ "${status}" != "success" && "${CONTINUE_ON_FAILURE}" != "yes" ]]; then
    return "${exit_code}"
  fi
  return 0
}

run_execution_plan() {
  local entry
  for entry in "${SELECTED_SCRIPTS[@]}"; do
    execute_child_script "${entry}"
  done
}

overall_status() {
  if grep -q $'\tfailure\t' "${RUN_CATALOG_PATH}" 2>/dev/null; then
    printf 'failure'
  elif grep -q $'\tdry-run\t' "${RUN_CATALOG_PATH}" 2>/dev/null; then
    printf 'dry-run'
  else
    printf 'success'
  fi
}

write_run_state() {
  local ended_at ended_epoch duration status
  ended_at="$(now_utc)"
  ended_epoch="$(now_epoch)"
  duration="$((ended_epoch - SCRIPT_STARTED_EPOCH))"
  status="$(overall_status)"
  cat > "${RUN_STATE_PATH}" <<EOF
RUN_ID=${RUN_ID}
SCRIPT_ID=${SCRIPT_ID}
SCRIPT_NAME=${SCRIPT_NAME}
SCRIPT_VERSION=${SCRIPT_VERSION}
PROJECT_NAME=${PROJECT_NAME}
PROJECT_ROOT=${PROJECT_ROOT}
EXECUTION_TARGET=${EXECUTION_TARGET}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME}
IMAGE_REF=${IMAGE_REF}
STARTED_AT=${SCRIPT_STARTED_AT}
ENDED_AT=${ended_at}
DURATION_SECONDS=${duration}
FINAL_STATUS=${status}
REPORT_PATH=${REPORT_PATH}
RUN_CATALOG_PATH=${RUN_CATALOG_PATH}
AUDIT_LOG=${AUDIT_LOG}
EOF
}

write_report() {
  local ended_at ended_epoch duration status
  ended_at="$(now_utc)"
  ended_epoch="$(now_epoch)"
  duration="$((ended_epoch - SCRIPT_STARTED_EPOCH))"
  status="$(overall_status)"
  cat > "${REPORT_PATH}" <<EOF
# ${SCRIPT_ID} ${SCRIPT_TITLE} Execution Report

| Field | Value |
|-------|-------|
| Script | ${SCRIPT_NAME} |
| Version | ${SCRIPT_VERSION} |
| Run ID | ${RUN_ID} |
| Project | ${PROJECT_NAME} |
| Project root | ${PROJECT_ROOT} |
| Target | ${EXECUTION_TARGET} |
| Container runtime | ${CONTAINER_RUNTIME} |
| Image | ${IMAGE_REF} |
| Started at | ${SCRIPT_STARTED_AT} |
| Ended at | ${ended_at} |
| Duration seconds | ${duration} |
| Final status | ${status} |
| Continue on failure | ${CONTINUE_ON_FAILURE} |
| Dry run | ${DRY_RUN} |

## Child Script Results

| Step | Script | Workflow | Status | Duration seconds | Exit code |
|------|--------|----------|--------|-----------------:|----------:|
EOF
  tail -n +2 "${RUN_CATALOG_PATH}" | while IFS=$'\t' read -r step script title workflow child_status started ended child_duration exit_code; do
    printf '| %s | %s | %s | %s | %s | %s |\n' "${step}" "${script}" "${workflow}" "${child_status}" "${child_duration}" "${exit_code}" >> "${REPORT_PATH}"
  done
  cat >> "${REPORT_PATH}" <<EOF

## Portability Contract

This orchestrator report is the master execution ledger. Domain-specific child
reports remain in their own .foundation/<domain>/ directories. Downstream CI,
HPC, AWS, governance, and audit workflows should read run_state.env and
run_catalog.tsv first, then inspect child reports for domain evidence.
EOF
}

hash_artifact() {
  foundation_hash_file "$1"
}

write_integrity_artifacts() {
  : > "${CHECKSUMS_PATH}"
  : > "${MANIFEST_PATH}"
  local artifact hash
  for artifact in "${AUDIT_LOG}" "${RUN_CATALOG_PATH}" "${RUN_STATE_PATH}" "${REPORT_PATH}"; do
    [[ -f "${artifact}" ]] || continue
    hash="$(hash_artifact "${artifact}")"
    printf '%s  %s\n' "${hash}" "${artifact}" >> "${CHECKSUMS_PATH}"
    printf '{"run_id":"%s","artifact":"%s","sha256":"%s","purpose":"%s","importance":10}\n' \
      "$(json_escape "${RUN_ID}")" \
      "$(json_escape "${artifact}")" \
      "$(json_escape "${hash}")" \
      "$(json_escape "Foundation orchestrator artifact")" >> "${MANIFEST_PATH}"
  done
}

sign_integrity_artifacts() {
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
  FINAL_STATUS="$(overall_status)"
  write_run_state
  write_report
  write_integrity_artifacts
  sign_integrity_artifacts
  write_audit "${SCRIPT_ID}.complete" "${FINAL_STATUS}" "report=${REPORT_PATH}"
  info "Foundation orchestration complete. Status: ${FINAL_STATUS}. Report: ${REPORT_PATH}"
  printf 'Final report: %s\n' "${REPORT_PATH}"
}

on_error() {
  local line="$1" code="$2"
  FINAL_STATUS="failure"
  if [[ -n "${AUDIT_LOG}" && -d "$(dirname "${AUDIT_LOG}")" ]]; then
    write_audit "${SCRIPT_ID}.failure" "failure" "line=${line} exit=${code} child=${CURRENT_CHILD_SCRIPT}"
    write_run_state || true
    write_report || true
  fi
  warn "Foundation orchestration failed at line ${line} with exit code ${code}."
  [[ -n "${CURRENT_CHILD_SCRIPT}" ]] && warn "Current child script: ${CURRENT_CHILD_SCRIPT}"
  [[ -n "${REPORT_PATH}" ]] && warn "Report path: ${REPORT_PATH}"
}
trap 'on_error ${LINENO} $?' ERR

main() {
  parse_args "$@"
  validate_cli
  resolve_paths
  initialize_evidence
  build_execution_plan
  run_execution_plan
  finish_success
  [[ "$(overall_status)" == "failure" ]] && return 1
  return 0
}

main "$@"
'@

[System.IO.File]::WriteAllText($targetPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote $targetPath"
