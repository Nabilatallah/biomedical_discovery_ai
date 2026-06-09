$base = 'C:\biodiscovery\01_foundation'
$files = @(
  @{Name='b001_02_aws_execution_preflight.sh'; Suffix='aws'},
  @{Name='b001_03_hpc_execution_preflight.sh'; Suffix='hpc'},
  @{Name='b001_04_policy_governance_preflight.sh'; Suffix='policy'},
  @{Name='b001_05_contract_architecture_preflight.sh'; Suffix='contracts_architecture'},
  @{Name='b001_06_hipaa_compliance_preflight.sh'; Suffix='hipaa'}
)

$parserBlock = @'
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
EXECUTION_TARGET="${EXECUTION_TARGET:-auto}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
OUTPUT_ROOT="${OUTPUT_ROOT:-.}"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
QUIET="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name) PROJECT_NAME="${2:-}"; shift 2 ;;
    --target) EXECUTION_TARGET="${2:-}"; shift 2 ;;
    --container-runtime) CONTAINER_RUNTIME="${2:-}"; shift 2 ;;
    --output-root) OUTPUT_ROOT="${2:-}"; shift 2 ;;
    --image) IMAGE_REF="${2:-}"; shift 2 ;;
    --quiet) QUIET="yes"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--project-name NAME] [--target auto|local|hpc|aws] [--container-runtime auto|docker|apptainer|none] [--output-root PATH] [--image REF] [--quiet]
EOF
      exit 0
      ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

case "${EXECUTION_TARGET}" in auto|local|hpc|aws) ;; *) fail "Invalid target: ${EXECUTION_TARGET}" ;; esac
case "${CONTAINER_RUNTIME}" in auto|docker|apptainer|none) ;; *) fail "Invalid container runtime: ${CONTAINER_RUNTIME}" ;; esac
OUTPUT_ROOT="$(foundation_absolute_dir "${OUTPUT_ROOT}")"
PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"
'@

foreach ($f in $files) {
  $path = Join-Path $base $f.Name
  $text = [System.IO.File]::ReadAllText($path)
  $original = $text

  $text = $text -replace 'PROJECT_NAME="\$\{PROJECT_NAME:-biodiscoveryai\}"\r?\n', ($parserBlock + "`n")
  $text = $text.Replace('OUT="${PROJECT_NAME}/.foundation/' + $f.Suffix + '"', 'OUT="${PROJECT_ROOT}/.foundation/' + $f.Suffix + '"')
  $text = $text.Replace('"${PROJECT_NAME}/', '"${PROJECT_ROOT}/')
  $text = $text.Replace('(cd "${PROJECT_NAME}"', '(cd "${PROJECT_ROOT}"')

  if ($text -ne $original) {
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Output "Updated $($f.Name)"
  }
}
