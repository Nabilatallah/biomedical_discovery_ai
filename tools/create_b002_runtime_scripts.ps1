$base = 'C:\biodiscovery\02_runtime'
$templatePath = 'C:\Users\nabil\Documents\biomedical_discovery_ai\tools\templates\b002_task_script.template.sh'
New-Item -ItemType Directory -Force -Path $base | Out-Null

$tasks = @(
  @{Id='b002_01'; File='b002_01_runtime_contract.sh'; Name='runtime-contract'; Phase='B002.01'; Domain='Runtime baseline'; Title='Runtime Contract'; Workflow='Runtime baseline'; Summary='Reads B001 outputs, validates foundation state, and defines service runtime conventions.'; Root='runtime/baseline'; Evidence='runtime_contract'; Components=@(
    @('runtime-contract','Defines portable runtime conventions for all services.','contract'),
    @('foundation-state-validator','Validates expected B001 foundation evidence before runtime implementation.','validator'),
    @('service-conventions','Defines health, audit, policy, observability, validation, and container conventions.','standard')
  )},
  @{Id='b002_02'; File='b002_02_service_factory.sh'; Name='service-factory'; Phase='B002.02'; Domain='Service factory'; Title='Service Factory'; Workflow='Service factory'; Summary='Turns service templates into real runnable FastAPI services.'; Root='tools/service-factory/components'; Evidence='service_factory'; Components=@(
    @('fastapi-template','Reusable FastAPI service template with health and runtime contract endpoints.','template'),
    @('service-generator','Generator entrypoint for creating new runtime services.','tool'),
    @('container-template','Dockerfile and container runtime convention for generated services.','container')
  )},
  @{Id='b002_03'; File='b002_03_core_services_bootstrap.sh'; Name='core-services-bootstrap'; Phase='B002.03'; Domain='Core services'; Title='Core Services Bootstrap'; Workflow='Core service implementation'; Summary='Implements API gateway, auth, tenant, governance, policy, audit, workflow, notification, and observability service skeletons.'; Root='apps/core-services'; Evidence='core_services_bootstrap'; Components=@(
    @('api-gateway','External API entry point service skeleton.','service'),
    @('auth-service','Authentication and identity service skeleton.','service'),
    @('tenant-service','Tenant isolation and tenant metadata service skeleton.','service'),
    @('governance-service','Governance runtime service skeleton.','service'),
    @('policy-service','Policy decision service skeleton.','service'),
    @('audit-service','Audit event ingestion and query service skeleton.','service'),
    @('workflow-service','Workflow execution service skeleton.','service'),
    @('notification-service','Notification delivery service skeleton.','service'),
    @('observability-service','Runtime observability service skeleton.','service')
  )},
  @{Id='b002_04'; File='b002_04_scientific_services_bootstrap.sh'; Name='scientific-services-bootstrap'; Phase='B002.04'; Domain='Scientific services'; Title='Scientific Services Bootstrap'; Workflow='Scientific service implementation'; Summary='Implements ingestion, parser, NLP, ontology, retrieval, RAG, contradiction, confidence, and validation service skeletons.'; Root='apps/scientific-services'; Evidence='scientific_services_bootstrap'; Components=@(
    @('ingestion-service','Scientific source ingestion service skeleton.','service'),
    @('parser-service','Scientific document parsing service skeleton.','service'),
    @('nlp-service','Biomedical NLP processing service skeleton.','service'),
    @('ontology-service','Ontology mapping and normalization service skeleton.','service'),
    @('retrieval-service','Evidence retrieval service skeleton.','service'),
    @('rag-service','Grounded generation orchestration service skeleton.','service'),
    @('contradiction-service','Contradiction detection service skeleton.','service'),
    @('confidence-service','Confidence scoring service skeleton.','service'),
    @('validation-service','Scientific validation service skeleton.','service')
  )},
  @{Id='b002_05'; File='b002_05_shared_sdks.sh'; Name='shared-sdks'; Phase='B002.05'; Domain='Shared SDKs'; Title='Shared SDKs'; Workflow='Shared SDK implementation'; Summary='Creates reusable Python packages for schemas, audit, auth, policies, events, validation, and retrieval.'; Root='packages'; Evidence='shared_sdks'; Components=@(
    @('schemas-sdk','Shared schema models and validation helpers.','sdk'),
    @('audit-sdk','Shared audit event writer and envelope helpers.','sdk'),
    @('auth-sdk','Shared authentication and authorization integration helpers.','sdk'),
    @('policy-sdk','Shared policy decision client helpers.','sdk'),
    @('events-sdk','Shared event envelope and publishing helpers.','sdk'),
    @('validation-sdk','Shared validation and evidence helpers.','sdk'),
    @('retrieval-sdk','Shared retrieval, citation, and ranking helpers.','sdk')
  )},
  @{Id='b002_06'; File='b002_06_contracts_implementation.sh'; Name='contracts-implementation'; Phase='B002.06'; Domain='Contracts'; Title='Contracts Implementation'; Workflow='Contract implementation'; Summary='Converts B001 placeholders into OpenAPI, JSON Schema, event schema, and policy contracts.'; Root='contracts/runtime'; Evidence='contracts_implementation'; Components=@(
    @('openapi-contracts','Runtime OpenAPI contract set.','contract'),
    @('json-schemas','JSON Schema contract set.','contract'),
    @('event-schemas','Runtime event schema contract set.','contract'),
    @('policy-contracts','Policy input/output contract set.','contract')
  )},
  @{Id='b002_07'; File='b002_07_persistence_bootstrap.sh'; Name='persistence-bootstrap'; Phase='B002.07'; Domain='Persistence'; Title='Persistence Bootstrap'; Workflow='Persistence implementation'; Summary='Adds Postgres, Neo4j, OpenSearch, migration folders, and local compose wiring.'; Root='persistence/runtime'; Evidence='persistence_bootstrap'; Components=@(
    @('postgres-runtime','Relational persistence runtime and migration lane.','database'),
    @('neo4j-runtime','Graph persistence runtime and migration lane.','database'),
    @('opensearch-runtime','Search persistence runtime and index lane.','database'),
    @('migration-runner','Baseline migration execution lane.','tool')
  )},
  @{Id='b002_08'; File='b002_08_event_bus_bootstrap.sh'; Name='event-bus-bootstrap'; Phase='B002.08'; Domain='Messaging'; Title='Event Bus Bootstrap'; Workflow='Messaging implementation'; Summary='Adds queue/event substrate, topics, event envelope, retry, and dead-letter conventions.'; Root='messaging'; Evidence='event_bus_bootstrap'; Components=@(
    @('event-envelope','Canonical event envelope implementation.','contract'),
    @('topic-registry','Topic registry and naming convention.','registry'),
    @('retry-policy','Retry and backoff policy lane.','policy'),
    @('dead-letter-queue','Dead-letter queue handling lane.','queue')
  )},
  @{Id='b002_09'; File='b002_09_observability_runtime.sh'; Name='observability-runtime'; Phase='B002.09'; Domain='Observability'; Title='Observability Runtime'; Workflow='Observability implementation'; Summary='Adds OpenTelemetry, Prometheus metrics, structured logs, Grafana dashboard placeholders.'; Root='observability/runtime'; Evidence='observability_runtime'; Components=@(
    @('opentelemetry-runtime','OpenTelemetry tracing and metrics lane.','observability'),
    @('prometheus-metrics','Prometheus metrics and scrape convention lane.','observability'),
    @('structured-logging','Structured JSON logging lane.','observability'),
    @('grafana-dashboards','Grafana dashboard placeholder lane.','observability')
  )},
  @{Id='b002_10'; File='b002_10_security_runtime.sh'; Name='security-runtime'; Phase='B002.10'; Domain='Security runtime'; Title='Security Runtime'; Workflow='Security runtime implementation'; Summary='Adds auth middleware, RBAC/ABAC hooks, secrets pattern, DLP, and biosecurity placeholders.'; Root='security/runtime'; Evidence='security_runtime'; Components=@(
    @('auth-middleware','Authentication middleware runtime lane.','security'),
    @('rbac-abac-hooks','RBAC and ABAC authorization hooks.','security'),
    @('secrets-pattern','Secrets access and redaction pattern.','security'),
    @('dlp-boundary','Data loss prevention boundary lane.','security'),
    @('biosecurity-boundary','Biosecurity misuse prevention boundary lane.','security')
  )},
  @{Id='b002_11'; File='b002_11_policy_runtime.sh'; Name='policy-runtime'; Phase='B002.11'; Domain='Governance runtime'; Title='Policy Runtime'; Workflow='Governance runtime implementation'; Summary='Adds OPA/Rego policy execution and audit hooks around service actions.'; Root='governance/runtime'; Evidence='policy_runtime'; Components=@(
    @('opa-client','OPA policy execution client lane.','governance'),
    @('rego-policy-bundle','Rego policy bundle lane.','governance'),
    @('audit-policy-hook','Audit hook around policy decisions.','governance'),
    @('decision-logger','Policy decision logging lane.','governance')
  )},
  @{Id='b002_12'; File='b002_12_data_connectors_bootstrap.sh'; Name='data-connectors-bootstrap'; Phase='B002.12'; Domain='Data connectors'; Title='Data Connectors Bootstrap'; Workflow='Data connector implementation'; Summary='Implements connector interfaces for PubMed, ClinicalTrials, FDA, EHR, and omics lanes.'; Root='connectors/data'; Evidence='data_connectors_bootstrap'; Components=@(
    @('pubmed-connector','PubMed connector interface skeleton.','connector'),
    @('clinicaltrials-connector','ClinicalTrials connector interface skeleton.','connector'),
    @('fda-connector','FDA connector interface skeleton.','connector'),
    @('ehr-connector','EHR connector interface skeleton with privacy boundary.','connector'),
    @('omics-connector','Lab omics connector interface skeleton.','connector')
  )},
  @{Id='b002_13'; File='b002_13_retrieval_runtime.sh'; Name='retrieval-runtime'; Phase='B002.13'; Domain='Retrieval stack'; Title='Retrieval Runtime'; Workflow='Retrieval implementation'; Summary='Adds vector store interface, embedding pipeline, ranking, and citation/evidence object model.'; Root='intelligence/retrieval'; Evidence='retrieval_runtime'; Components=@(
    @('vector-store-interface','Vector store interface skeleton.','retrieval'),
    @('embedding-pipeline','Embedding pipeline skeleton.','retrieval'),
    @('ranking-engine','Ranking service skeleton.','retrieval'),
    @('citation-model','Citation and evidence object model.','retrieval')
  )},
  @{Id='b002_14'; File='b002_14_graph_runtime.sh'; Name='graph-runtime'; Phase='B002.14'; Domain='Graph stack'; Title='Graph Runtime'; Workflow='Graph implementation'; Summary='Adds graph schema, ontology loader, graph query service, and provenance edge model.'; Root='intelligence/graph'; Evidence='graph_runtime'; Components=@(
    @('graph-schema','Graph schema implementation lane.','graph'),
    @('ontology-loader','Ontology loading runtime lane.','graph'),
    @('graph-query-service','Graph query service skeleton.','graph'),
    @('provenance-edge-model','Provenance edge model lane.','graph')
  )},
  @{Id='b002_15'; File='b002_15_rag_review_runtime.sh'; Name='rag-review-runtime'; Phase='B002.15'; Domain='RAG and review'; Title='RAG and Review Runtime'; Workflow='RAG/review implementation'; Summary='Adds claim-grounding, citation enforcement, review state machine, and decision brief draft flow.'; Root='intelligence/rag-review'; Evidence='rag_review_runtime'; Components=@(
    @('claim-grounding','Claim grounding runtime lane.','rag'),
    @('citation-enforcement','Citation enforcement runtime lane.','rag'),
    @('review-state-machine','Reviewer workflow state machine lane.','review'),
    @('decision-brief-flow','Decision brief draft flow lane.','review')
  )},
  @{Id='b002_16'; File='b002_16_validation_harness.sh'; Name='validation-harness'; Phase='B002.16'; Domain='Validation harness'; Title='Validation Harness'; Workflow='Validation implementation'; Summary='Adds tests for hallucination, contradiction, citation integrity, regression, and reviewer calibration.'; Root='validation/harness'; Evidence='validation_harness'; Components=@(
    @('hallucination-tests','Hallucination evaluation lane.','validation'),
    @('contradiction-tests','Contradiction evaluation lane.','validation'),
    @('citation-integrity-tests','Citation integrity validation lane.','validation'),
    @('regression-tests','Runtime regression test lane.','validation'),
    @('reviewer-calibration','Reviewer calibration test lane.','validation')
  )},
  @{Id='b002_17'; File='b002_17_local_compose_runtime.sh'; Name='local-compose-runtime'; Phase='B002.17'; Domain='Local container runtime'; Title='Local Compose Runtime'; Workflow='Local runtime implementation'; Summary='Creates Docker Compose stack for local platform execution.'; Root='runtime/local-compose'; Evidence='local_compose_runtime'; Components=@(
    @('compose-stack','Local Docker Compose stack lane.','container'),
    @('service-network','Local service network lane.','container'),
    @('local-env','Local environment configuration lane.','config')
  )},
  @{Id='b002_18'; File='b002_18_hpc_runtime.sh'; Name='hpc-runtime'; Phase='B002.18'; Domain='HPC runtime'; Title='HPC Runtime'; Workflow='HPC runtime implementation'; Summary='Creates Apptainer build/run files and Slurm launcher scripts.'; Root='runtime/hpc'; Evidence='hpc_runtime'; Components=@(
    @('apptainer-definition','Apptainer definition lane.','hpc'),
    @('slurm-launcher','Slurm launcher lane.','hpc'),
    @('hpc-module-contract','HPC module and filesystem contract lane.','hpc')
  )},
  @{Id='b002_19'; File='b002_19_aws_runtime.sh'; Name='aws-runtime'; Phase='B002.19'; Domain='AWS runtime'; Title='AWS Runtime'; Workflow='AWS runtime implementation'; Summary='Creates ECS/EKS/Batch-ready runtime scaffolds and ECR image conventions.'; Root='runtime/aws'; Evidence='aws_runtime'; Components=@(
    @('ecr-conventions','ECR image convention lane.','aws'),
    @('ecs-runtime','ECS runtime scaffold lane.','aws'),
    @('eks-runtime','EKS runtime scaffold lane.','aws'),
    @('batch-runtime','AWS Batch runtime scaffold lane.','aws')
  )},
  @{Id='b002_20'; File='b002_20_cicd_runtime.sh'; Name='cicd-runtime'; Phase='B002.20'; Domain='CI/CD implementation'; Title='CI/CD Runtime'; Workflow='CI/CD implementation'; Summary='Adds real GitHub Actions jobs for tests, scans, contracts, containers, and SBOM.'; Root='cicd/runtime'; Evidence='cicd_runtime'; Components=@(
    @('runtime-ci','Runtime CI workflow lane.','ci'),
    @('contract-checks','Contract checks workflow lane.','ci'),
    @('container-builds','Container build workflow lane.','ci'),
    @('sbom-generation','SBOM workflow lane.','ci')
  )},
  @{Id='b002_21'; File='b002_21_devsecops_scans.sh'; Name='devsecops-scans'; Phase='B002.21'; Domain='DevSecOps scans'; Title='DevSecOps Scans'; Workflow='DevSecOps implementation'; Summary='Activates gitleaks, semgrep, trivy, grype, syft, checkov, and hadolint.'; Root='security/devsecops'; Evidence='devsecops_scans'; Components=@(
    @('gitleaks-scan','Secret scanning lane.','security-scan'),
    @('semgrep-sast','SAST scanning lane.','security-scan'),
    @('trivy-scan','Filesystem/container vulnerability scanning lane.','security-scan'),
    @('grype-scan','Dependency vulnerability scanning lane.','security-scan'),
    @('syft-sbom','SBOM generation lane.','security-scan'),
    @('checkov-iac','IaC security scanning lane.','security-scan'),
    @('hadolint-container','Dockerfile linting lane.','security-scan')
  )}
)

$template = [System.IO.File]::ReadAllText($templatePath)

foreach ($task in $tasks) {
  $componentLines = ($task.Components | ForEach-Object {
    "  `"$($_[0])|$($_[1])|$($_[2])`""
  }) -join "`n"
  $content = $template
  $content = $content.Replace('@SCRIPT_ID@', $task.Id)
  $content = $content.Replace('@SCRIPT_NAME@', $task.Name)
  $content = $content.Replace('@TITLE@', $task.Title)
  $content = $content.Replace('@SUMMARY@', $task.Summary)
  $content = $content.Replace('@PHASE@', $task.Phase)
  $content = $content.Replace('@DOMAIN@', $task.Domain)
  $content = $content.Replace('@WORKFLOW@', $task.Workflow)
  $content = $content.Replace('@ROOT@', $task.Root)
  $content = $content.Replace('@EVIDENCE_NAME@', $task.Evidence)
  $content = $content.Replace('@FILE_NAME@', $task.File)
  $content = $content.Replace('@COMPONENT_LINES@', $componentLines)
  [System.IO.File]::WriteAllText((Join-Path $base $task.File), $content, [System.Text.UTF8Encoding]::new($false))
  Write-Output "Wrote $($task.File)"
}

$entries = ($tasks | ForEach-Object { "  `"$($_.Id.Substring(5,2))|$($_.File)|$($_.Domain)|$($_.Workflow)`"" }) -join "`n"
$orchestrator = @'
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
# Developer Documentation Index for b002_22_runtime_orchestrator.sh
# ==============================================================================
#
# Section 01 - Design principles
#   Single Responsibility keeps this script focused on B002 runtime orchestration.
#   Open/Closed behavior allows new B002 scripts to be added to the run list.
#   Liskov-style substitution treats every child script through the same CLI,
#   timing, report, audit, and exit-status contract. Interface segregation keeps
#   the master report separate from child runtime reports. Dependency inversion
#   keeps orchestration dependent on child script files and generated catalogs,
#   not implementation internals.
#
# Section 02 - What this script does
#   Runs B002.01 through B002.21 in order, stops on first failure by default,
#   writes a master JSONL audit log, master Markdown report, run_state.env,
#   run_catalog.tsv, checksums, artifact manifest, optional signatures, and final
#   report location.
#
# Section 03 - How To Run On HPC
#   Direct:
#     /path/to/b002_22_runtime_orchestrator.sh --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /approved/project/storage
#
#   Slurm:
#     sbatch <<'SLURM_EOF'
#     #!/bin/bash
#     #SBATCH --job-name=bdai-b002-runtime
#     #SBATCH --time=01:00:00
#     #SBATCH --cpus-per-task=2
#     #SBATCH --mem=8G
#     /path/to/b002_22_runtime_orchestrator.sh --project-name biodiscoveryai --target hpc --container-runtime apptainer --output-root /approved/project/storage
#     SLURM_EOF
#
# Section 04 - How To Run On AWS Cloud
#   Docker:
#     docker run --rm -v "$PWD/out:/work" -v "$PWD:/workspace" biodiscoveryai/foundation-runner:0.3.0 \
#       /workspace/02_runtime/b002_22_runtime_orchestrator.sh --project-name biodiscoveryai --target aws --container-runtime docker --output-root /work
#
# Section 05 - What It Does
#
# | Area | Capability |
# |------|------------|
# | Runtime focus | Orchestrates the complete B002 concrete runtime implementation layer. |
# | Execution order | Runs B002.01 through B002.21 by default. |
# | Selection controls | Supports --from, --to, --only, and --skip. |
# | Failure behavior | Stops on first failure unless --continue-on-failure is supplied. |
# | Auditability | Writes JSONL audit, run catalog, checksums, manifest, and signing status. |
# | Reporting | Writes master Markdown report with start/end/duration/status per child script. |
#
# Section 06 - Artifacts Created When The Script Runs
#
# | Artifact name | Purpose | Dependency | Importance score |
# |---------------|---------|------------|-----------------:|
# | <project>/.runtime/runtime_orchestrator/report.md | Master runtime report | date, cat | 10 |
# | <project>/.runtime/runtime_orchestrator/audit.jsonl | Master JSONL audit trail | date, sed | 10 |
# | <project>/.runtime/runtime_orchestrator/run_state.env | Final runtime state | cat | 10 |
# | <project>/.runtime/runtime_orchestrator/run_catalog.tsv | Per-script execution ledger | printf | 10 |
# | <project>/.runtime/runtime_orchestrator/checksums.txt | Integrity checksums | sha256sum/shasum/openssl | 10 |
# | <project>/.runtime/runtime_orchestrator/manifest.jsonl | Artifact manifest | sha256sum/shasum/openssl | 10 |
#
# Section 07 - Portability contract
#   Downstream local, HPC, AWS, CI, and audit automation should read run_state.env
#   and run_catalog.tsv first, then inspect child reports under .runtime/<task>/.
#
# Section 08 - Start/end time, logging, and reporting
#   Records master start/end time, duration, status, child timing, child exit
#   codes, audit events, integrity artifacts, signing status, and final report.
# ==============================================================================

SCRIPT_ID="b002_22"
SCRIPT_NAME="runtime-orchestrator"
SCRIPT_VERSION="0.1.0"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
EXECUTION_TARGET="${EXECUTION_TARGET:-auto}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
OUTPUT_ROOT="${OUTPUT_ROOT:-.}"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
FROM_STEP="01"
TO_STEP="21"
ONLY_LIST=""
SKIP_LIST=""
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
SELECTED_SCRIPTS=()
B002_SCRIPTS=(
@SCRIPT_ENTRIES@
)

usage() {
  cat <<'EOF'
BioDiscoveryAI b002_22 Runtime Orchestrator

Usage:
  b002_22_runtime_orchestrator.sh [options]

Options:
  --project-name NAME           Project directory name. Default: biodiscoveryai
  --target TARGET               auto, local, hpc, aws. Default: auto
  --container-runtime RUNTIME   auto, docker, apptainer, none. Default: auto
  --output-root PATH            Absolute or resolvable project parent path. Default: current directory
  --image REF                   Container image reference for child metadata
  --from NN                     First script number to run. Default: 01
  --to NN                       Last script number to run. Default: 21
  --only LIST                   Comma-separated script numbers to run
  --skip LIST                   Comma-separated script numbers to skip
  --continue-on-failure         Continue after a child script failure
  --dry-run                     Print plan but do not execute child scripts
  --quiet                       Reduce informational logging
  -h, --help                    Show this help
EOF
}

normalize_step() { local value="$1"; [[ "${value}" =~ ^[0-9]+$ ]] || fail "Invalid step number: ${value}"; printf '%02d' "${value#0}"; }
step_to_int() { printf '%d' "10#$1"; }
csv_contains_step() {
  local csv="$1" step="$2" item normalized
  [[ -n "${csv}" ]] || return 1
  IFS=',' read -r -a items <<< "${csv}"
  for item in "${items[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -n "${item}" ]] || continue
    normalized="$(normalize_step "${item}")"
    [[ "${normalized}" == "${step}" ]] && return 0
  done
  return 1
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
      --continue-on-failure) CONTINUE_ON_FAILURE="yes"; shift ;;
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
  [[ "$(step_to_int "${FROM_STEP}")" -le "$(step_to_int "${TO_STEP}")" ]] || fail "--from must be <= --to."
}

resolve_paths() {
  OUTPUT_ROOT="$(foundation_absolute_dir "${OUTPUT_ROOT}")"
  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"
  EVIDENCE_DIR="${PROJECT_ROOT}/.runtime/runtime_orchestrator"
  AUDIT_LOG="${EVIDENCE_DIR}/audit.jsonl"
  REPORT_PATH="${EVIDENCE_DIR}/report.md"
  RUN_STATE_PATH="${EVIDENCE_DIR}/run_state.env"
  RUN_CATALOG_PATH="${EVIDENCE_DIR}/run_catalog.tsv"
  CHECKSUMS_PATH="${EVIDENCE_DIR}/checksums.txt"
  MANIFEST_PATH="${EVIDENCE_DIR}/manifest.jsonl"
  SIGNING_STATUS="${EVIDENCE_DIR}/signing_status.md"
}

write_audit() { foundation_write_jsonl "${AUDIT_LOG}" "$1" "$2" "run_id=${RUN_ID} $3"; }

initialize_evidence() {
  mkdir -p "${EVIDENCE_DIR}"
  : > "${AUDIT_LOG}"
  printf 'step\tscript\tdomain\tworkflow\tstatus\tstarted_at\tended_at\tduration_seconds\texit_code\n' > "${RUN_CATALOG_PATH}"
  write_audit "${SCRIPT_ID}.start" "started" "project=${PROJECT_NAME} target=${EXECUTION_TARGET} runtime=${CONTAINER_RUNTIME}"
}

build_execution_plan() {
  SELECTED_SCRIPTS=()
  local entry step script domain workflow step_int from_int to_int
  from_int="$(step_to_int "${FROM_STEP}")"; to_int="$(step_to_int "${TO_STEP}")"
  for entry in "${B002_SCRIPTS[@]}"; do
    IFS='|' read -r step script domain workflow <<< "${entry}"
    step_int="$(step_to_int "${step}")"
    [[ -n "${ONLY_LIST}" ]] && ! csv_contains_step "${ONLY_LIST}" "${step}" && continue
    [[ -z "${ONLY_LIST}" && "${step_int}" -lt "${from_int}" ]] && continue
    [[ -z "${ONLY_LIST}" && "${step_int}" -gt "${to_int}" ]] && continue
    csv_contains_step "${SKIP_LIST}" "${step}" && continue
    [[ -f "${SCRIPT_DIR}/${script}" ]] || fail "Required child script not found: ${SCRIPT_DIR}/${script}"
    SELECTED_SCRIPTS+=("${entry}")
  done
  [[ "${#SELECTED_SCRIPTS[@]}" -gt 0 ]] || fail "No child scripts selected."
}

execute_child_script() {
  local entry="$1" step script domain workflow started_at started_epoch ended_at ended_epoch duration exit_code status
  IFS='|' read -r step script domain workflow <<< "${entry}"
  CURRENT_CHILD_SCRIPT="${script}"
  started_at="$(now_utc)"; started_epoch="$(now_epoch)"
  write_audit "${SCRIPT_ID}.child.start" "started" "step=${step} script=${script}"
  if [[ "${DRY_RUN}" == "yes" ]]; then
    status="dry-run"; exit_code=0
    info "DRY RUN: would run ${script}"
  elif bash "${SCRIPT_DIR}/${script}" --project-name "${PROJECT_NAME}" --target "${EXECUTION_TARGET}" --container-runtime "${CONTAINER_RUNTIME}" --output-root "${OUTPUT_ROOT}" --image "${IMAGE_REF}" ${QUIET:+--quiet}; then
    status="success"; exit_code=0
  else
    exit_code=$?; status="failure"
  fi
  ended_at="$(now_utc)"; ended_epoch="$(now_epoch)"; duration="$((ended_epoch - started_epoch))"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${step}" "${script}" "${domain}" "${workflow}" "${status}" "${started_at}" "${ended_at}" "${duration}" "${exit_code}" >> "${RUN_CATALOG_PATH}"
  write_audit "${SCRIPT_ID}.child.complete" "${status}" "step=${step} script=${script} exit_code=${exit_code} duration=${duration}"
  CURRENT_CHILD_SCRIPT=""
  [[ "${status}" == "failure" && "${CONTINUE_ON_FAILURE}" != "yes" ]] && return "${exit_code}"
  return 0
}

run_execution_plan() { local entry; for entry in "${SELECTED_SCRIPTS[@]}"; do execute_child_script "${entry}"; done; }
overall_status() { if grep -q $'\tfailure\t' "${RUN_CATALOG_PATH}" 2>/dev/null; then printf failure; elif grep -q $'\tdry-run\t' "${RUN_CATALOG_PATH}" 2>/dev/null; then printf dry-run; else printf success; fi; }

write_run_state() {
  local ended_at ended_epoch duration status
  ended_at="$(now_utc)"; ended_epoch="$(now_epoch)"; duration="$((ended_epoch - SCRIPT_STARTED_EPOCH))"; status="$(overall_status)"
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
  ended_at="$(now_utc)"; ended_epoch="$(now_epoch)"; duration="$((ended_epoch - SCRIPT_STARTED_EPOCH))"; status="$(overall_status)"
  cat > "${REPORT_PATH}" <<EOF
# ${SCRIPT_ID} Runtime Orchestrator Execution Report

| Field | Value |
|-------|-------|
| Script | ${SCRIPT_NAME} |
| Version | ${SCRIPT_VERSION} |
| Run ID | ${RUN_ID} |
| Project root | ${PROJECT_ROOT} |
| Target | ${EXECUTION_TARGET} |
| Container runtime | ${CONTAINER_RUNTIME} |
| Started at | ${SCRIPT_STARTED_AT} |
| Ended at | ${ended_at} |
| Duration seconds | ${duration} |
| Final status | ${status} |

## Child Script Results

| Step | Script | Workflow | Status | Duration seconds | Exit code |
|------|--------|----------|--------|-----------------:|----------:|
EOF
  tail -n +2 "${RUN_CATALOG_PATH}" | while IFS=$'\t' read -r step script domain workflow child_status started ended child_duration exit_code; do
    printf '| %s | %s | %s | %s | %s | %s |\n' "${step}" "${script}" "${workflow}" "${child_status}" "${child_duration}" "${exit_code}" >> "${REPORT_PATH}"
  done
}

write_integrity_artifacts() {
  : > "${CHECKSUMS_PATH}"; : > "${MANIFEST_PATH}"
  local artifact hash
  for artifact in "${AUDIT_LOG}" "${RUN_CATALOG_PATH}" "${RUN_STATE_PATH}" "${REPORT_PATH}"; do
    [[ -f "${artifact}" ]] || continue
    hash="$(foundation_hash_file "${artifact}")"
    printf '%s  %s\n' "${hash}" "${artifact}" >> "${CHECKSUMS_PATH}"
    printf '{"run_id":"%s","artifact":"%s","sha256":"%s","purpose":"B002 runtime orchestrator artifact","importance":10}\n' "$(json_escape "${RUN_ID}")" "$(json_escape "${artifact}")" "$(json_escape "${hash}")" >> "${MANIFEST_PATH}"
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
    tool=none; status=unsigned-tool-unavailable
    if command -v cosign >/dev/null 2>&1; then cosign sign-blob --yes "${artifact}" --output-signature "${artifact}.sig" >/dev/null 2>&1 && tool=cosign && status=signed || status=cosign-failed
    elif command -v gpg >/dev/null 2>&1; then gpg --batch --yes --armor --detach-sign "${artifact}" >/dev/null 2>&1 && tool=gpg && status=signed || status=gpg-failed
    fi
    printf '| %s | %s | %s |\n' "${artifact}" "${status}" "${tool}" >> "${SIGNING_STATUS}"
  done
}

finish() {
  local status
  status="$(overall_status)"
  write_run_state; write_report; write_integrity_artifacts; sign_integrity_artifacts
  write_audit "${SCRIPT_ID}.complete" "${status}" "report=${REPORT_PATH}"
  info "B002 runtime orchestration complete. Status: ${status}. Report: ${REPORT_PATH}"
  printf 'Final report: %s\n' "${REPORT_PATH}"
  [[ "${status}" == failure ]] && return 1 || return 0
}

on_error() {
  local line="$1" code="$2"
  if [[ -n "${AUDIT_LOG}" && -d "$(dirname "${AUDIT_LOG}")" ]]; then
    write_audit "${SCRIPT_ID}.failure" "failure" "line=${line} exit=${code} child=${CURRENT_CHILD_SCRIPT}"
  fi
  warn "B002 runtime orchestration failed at line ${line} with exit code ${code}."
  [[ -n "${CURRENT_CHILD_SCRIPT}" ]] && warn "Current child script: ${CURRENT_CHILD_SCRIPT}"
}
trap 'on_error ${LINENO} $?' ERR

main() {
  parse_args "$@"; validate_cli; resolve_paths; initialize_evidence; build_execution_plan; run_execution_plan; finish
}

main "$@"
'@
$orchestrator = $orchestrator.Replace('@SCRIPT_ENTRIES@', $entries)
[System.IO.File]::WriteAllText((Join-Path $base 'b002_22_runtime_orchestrator.sh'), $orchestrator, [System.Text.UTF8Encoding]::new($false))
Write-Output 'Wrote b002_22_runtime_orchestrator.sh'

$codeowners = @'
# BioDiscoveryAI B002 runtime CODEOWNERS
*.sh @platform-owner @security-owner
/b002_22_runtime_orchestrator.sh @platform-owner @security-owner @governance-owner
'@
[System.IO.File]::WriteAllText((Join-Path $base 'CODEOWNERS'), $codeowners, [System.Text.UTF8Encoding]::new($false))
Write-Output 'Wrote CODEOWNERS'
