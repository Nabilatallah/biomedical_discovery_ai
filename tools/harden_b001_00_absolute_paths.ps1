$path = 'C:\biodiscovery\01_foundation\b001_00_foundation_common.sh'
$text = [System.IO.File]::ReadAllText($path)
$original = $text

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

$text = $text -replace 'PROJECT_NAME="\$\{PROJECT_NAME:-biodiscoveryai\}"\r?\n', ($parserBlock + "`n")
$text = $text.Replace('OUT="${PROJECT_NAME}/.foundation/common"', 'OUT="${PROJECT_ROOT}/.foundation/common"')
$text = $text.Replace('"${PROJECT_NAME}/', '"${PROJECT_ROOT}/')
$text = $text.Replace('| Generated project copy | ${PROJECT_NAME}/lib/foundation_common.sh |', '| Generated project copy | ${PROJECT_ROOT}/lib/foundation_common.sh |')

if ($text -ne $original) {
  [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
  Write-Output 'Updated b001_00_foundation_common.sh'
}

$orchPath = 'C:\biodiscovery\01_foundation\b001_40_foundation_orchestrator.sh'
$orch = [System.IO.File]::ReadAllText($orchPath)
$old = @'
  if [[ "${step}" == "01" ]]; then
    args+=("--output-dir" "${PROJECT_ROOT}/.foundation/preflight")
  elif [[ "${step}" != "00" ]]; then
    args+=("--output-root" "${OUTPUT_ROOT}")
  fi
  if [[ "${step}" != "00" ]]; then
    args+=("--image" "${IMAGE_REF}")
  fi
'@
$new = @'
  if [[ "${step}" == "01" ]]; then
    args+=("--output-dir" "${PROJECT_ROOT}/.foundation/preflight")
  else
    args+=("--output-root" "${OUTPUT_ROOT}")
  fi
  args+=("--image" "${IMAGE_REF}")
'@
if ($orch.Contains($old)) {
  $orch = $orch.Replace($old, $new)
  [System.IO.File]::WriteAllText($orchPath, $orch, [System.Text.UTF8Encoding]::new($false))
  Write-Output 'Updated b001_40 child args for b001_00'
}
