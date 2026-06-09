$root = 'C:\biodiscovery'
$base = Join-Path $root '00_container\foundation-runner'
$scripts = Join-Path $base 'scripts'
$docs = Join-Path $base 'docs'
New-Item -ItemType Directory -Force -Path $base, $scripts, $docs | Out-Null

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
}

Write-Utf8NoBom (Join-Path $root '.dockerignore') @'
.git
.agents
.codex
archive
bd_001
biodiscoveryai
out
outputs
tmp
**/.foundation
**/.runtime
**/__pycache__
**/.pytest_cache
**/.mypy_cache
**/*.pyc
**/*.pyo
**/*.sif
**/*.sig
**/*.asc
'@

Write-Utf8NoBom (Join-Path $base 'VERSION') @'
0.3.0
'@

Write-Utf8NoBom (Join-Path $base 'requirements.txt') @'
fastapi==0.115.6
uvicorn[standard]==0.34.0
pydantic==2.10.4
pytest==8.3.4
httpx==0.28.1
PyYAML==6.0.2
jsonschema==4.23.0
prometheus-client==0.21.1
opentelemetry-api==1.29.0
opentelemetry-sdk==1.29.0
'@

Write-Utf8NoBom (Join-Path $base 'Dockerfile') @'
FROM python:3.12-slim-bookworm

ARG BDAI_IMAGE_VERSION=0.3.0
ARG INSTALL_DEVSECOPS_TOOLS=false

LABEL org.opencontainers.image.title="BioDiscoveryAI Foundation Runner"
LABEL org.opencontainers.image.description="Portable runner for B001 foundation and B002 runtime implementation scripts"
LABEL org.opencontainers.image.version="${BDAI_IMAGE_VERSION}"
LABEL org.opencontainers.image.vendor="BioDiscoveryAI"
LABEL org.opencontainers.image.source="biodiscovery/00_container/foundation-runner"

ENV PYTHONUNBUFFERED=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1
ENV FOUNDATION_ENABLE_SIGNING=no
ENV FOUNDATION_SIGNING_TIMEOUT_SECONDS=15
ENV BDAI_WORKSPACE=/workspace
ENV BDAI_OUTPUT_ROOT=/work

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      bats \
      ca-certificates \
      coreutils \
      curl \
      findutils \
      gawk \
      git \
      gnupg \
      grep \
      jq \
      make \
      openssl \
      procps \
      sed \
      shellcheck \
      tar \
      unzip \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY 00_container/foundation-runner/requirements.txt /opt/biodiscovery/requirements.txt
RUN python -m pip install --upgrade pip setuptools wheel \
    && python -m pip install -r /opt/biodiscovery/requirements.txt

COPY 00_container/foundation-runner/entrypoint.sh /usr/local/bin/bdai-entrypoint
RUN chmod +x /usr/local/bin/bdai-entrypoint

COPY 01_foundation /workspace/01_foundation
COPY 02_runtime /workspace/02_runtime
COPY 00_container /workspace/00_container

WORKDIR /workspace

ENTRYPOINT ["bdai-entrypoint"]
CMD ["bash"]
'@

Write-Utf8NoBom (Join-Path $base 'entrypoint.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

show_help() {
  cat <<'EOF'
BioDiscoveryAI Foundation Runner

Commands:
  b001      Run B001 foundation orchestrator
  b002      Run B002 runtime orchestrator
  shell     Open an interactive shell
  help      Show this help

Examples:
  bdai-entrypoint b001 --target hpc --container-runtime apptainer --output-root /work
  bdai-entrypoint b002 --target aws --container-runtime docker --output-root /work
EOF
}

case "${1:-help}" in
  b001)
    shift
    exec bash /workspace/01_foundation/b001_40_foundation_orchestrator.sh "$@"
    ;;
  b002)
    shift
    exec bash /workspace/02_runtime/b002_22_runtime_orchestrator.sh "$@"
    ;;
  shell)
    shift || true
    exec bash "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    exec "$@"
    ;;
esac
'@

Write-Utf8NoBom (Join-Path $base 'Apptainer.foundation-runner.def') @'
Bootstrap: docker
From: biodiscoveryai/foundation-runner:0.3.0

%labels
    org.opencontainers.image.title BioDiscoveryAI Foundation Runner
    org.opencontainers.image.version 0.3.0
    org.opencontainers.image.description Portable runner for B001 and B002 scripts

%environment
    export FOUNDATION_ENABLE_SIGNING=${FOUNDATION_ENABLE_SIGNING:-no}
    export FOUNDATION_SIGNING_TIMEOUT_SECONDS=${FOUNDATION_SIGNING_TIMEOUT_SECONDS:-15}
    export BDAI_WORKSPACE=/workspace
    export BDAI_OUTPUT_ROOT=/work

%runscript
    exec /usr/local/bin/bdai-entrypoint "$@"
'@

Write-Utf8NoBom (Join-Path $base 'docker-compose.foundation-runner.yml') @'
services:
  foundation-runner:
    image: biodiscoveryai/foundation-runner:0.3.0
    build:
      context: ../..
      dockerfile: 00_container/foundation-runner/Dockerfile
      args:
        BDAI_IMAGE_VERSION: "0.3.0"
    environment:
      FOUNDATION_ENABLE_SIGNING: "no"
      FOUNDATION_SIGNING_TIMEOUT_SECONDS: "15"
    volumes:
      - ../../out:/work
    command: ["help"]
'@

Write-Utf8NoBom (Join-Path $scripts 'build_docker.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${CONTAINER_DIR}/../.." && pwd)"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
REPORT_DIR="${CONTAINER_DIR}/reports"
REPORT_PATH="${REPORT_DIR}/docker_build_report.md"

mkdir -p "${REPORT_DIR}"
started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

docker build \
  -f "${CONTAINER_DIR}/Dockerfile" \
  -t "${IMAGE_REF}" \
  "${PROJECT_ROOT}"

ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "${REPORT_PATH}" <<EOF
# Foundation Runner Docker Build Report

| Field | Value |
|-------|-------|
| Image | ${IMAGE_REF} |
| Project root | ${PROJECT_ROOT} |
| Started at | ${started_at} |
| Ended at | ${ended_at} |
| Status | success |
EOF

printf 'Docker image built: %s\n' "${IMAGE_REF}"
printf 'Report: %s\n' "${REPORT_PATH}"
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b001_docker.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$(pwd)/out}"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
TARGET="${TARGET:-local}"

mkdir -p "${OUTPUT_ROOT}"

docker run --rm \
  -e FOUNDATION_ENABLE_SIGNING="${FOUNDATION_ENABLE_SIGNING:-no}" \
  -e FOUNDATION_SIGNING_TIMEOUT_SECONDS="${FOUNDATION_SIGNING_TIMEOUT_SECONDS:-15}" \
  -v "${OUTPUT_ROOT}:/work" \
  "${IMAGE_REF}" \
  b001 \
    --project-name "${PROJECT_NAME}" \
    --target "${TARGET}" \
    --container-runtime docker \
    --output-root /work \
    --image "${IMAGE_REF}" \
    "$@"
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b002_docker.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$(pwd)/out}"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
TARGET="${TARGET:-local}"

mkdir -p "${OUTPUT_ROOT}"

docker run --rm \
  -e FOUNDATION_ENABLE_SIGNING="${FOUNDATION_ENABLE_SIGNING:-no}" \
  -e FOUNDATION_SIGNING_TIMEOUT_SECONDS="${FOUNDATION_SIGNING_TIMEOUT_SECONDS:-15}" \
  -v "${OUTPUT_ROOT}:/work" \
  "${IMAGE_REF}" \
  b002 \
    --project-name "${PROJECT_NAME}" \
    --target "${TARGET}" \
    --container-runtime docker \
    --output-root /work \
    --image "${IMAGE_REF}" \
    "$@"
'@

Write-Utf8NoBom (Join-Path $scripts 'build_apptainer_from_docker.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
SIF_PATH="${SIF_PATH:-foundation-runner_0.3.0.sif}"

if command -v apptainer >/dev/null 2>&1; then
  apptainer build "${SIF_PATH}" "docker-daemon://${IMAGE_REF}"
elif command -v singularity >/dev/null 2>&1; then
  singularity build "${SIF_PATH}" "docker-daemon://${IMAGE_REF}"
else
  printf '[ERROR] apptainer or singularity is required.\n' >&2
  exit 1
fi

printf 'Apptainer/Singularity image built: %s\n' "${SIF_PATH}"
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b001_apptainer.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

SIF_PATH="${SIF_PATH:-foundation-runner_0.3.0.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$(pwd)/out}"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"

mkdir -p "${OUTPUT_ROOT}"

if command -v apptainer >/dev/null 2>&1; then
  apptainer exec --bind "${OUTPUT_ROOT}:/work" "${SIF_PATH}" b001 --project-name "${PROJECT_NAME}" --target hpc --container-runtime apptainer --output-root /work "$@"
elif command -v singularity >/dev/null 2>&1; then
  singularity exec --bind "${OUTPUT_ROOT}:/work" "${SIF_PATH}" b001 --project-name "${PROJECT_NAME}" --target hpc --container-runtime apptainer --output-root /work "$@"
else
  printf '[ERROR] apptainer or singularity is required.\n' >&2
  exit 1
fi
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b002_apptainer.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

SIF_PATH="${SIF_PATH:-foundation-runner_0.3.0.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$(pwd)/out}"
PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"

mkdir -p "${OUTPUT_ROOT}"

if command -v apptainer >/dev/null 2>&1; then
  apptainer exec --bind "${OUTPUT_ROOT}:/work" "${SIF_PATH}" b002 --project-name "${PROJECT_NAME}" --target hpc --container-runtime apptainer --output-root /work "$@"
elif command -v singularity >/dev/null 2>&1; then
  singularity exec --bind "${OUTPUT_ROOT}:/work" "${SIF_PATH}" b002 --project-name "${PROJECT_NAME}" --target hpc --container-runtime apptainer --output-root /work "$@"
else
  printf '[ERROR] apptainer or singularity is required.\n' >&2
  exit 1
fi
'@

Write-Utf8NoBom (Join-Path $scripts 'push_ecr.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:?Set AWS_REGION or AWS_DEFAULT_REGION}}"
LOCAL_IMAGE="${LOCAL_IMAGE:-biodiscoveryai/foundation-runner:0.3.0}"
ECR_REPOSITORY="${ECR_REPOSITORY:-biodiscoveryai/foundation-runner}"
ECR_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:0.3.0"

aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "${ECR_REPOSITORY}" >/dev/null

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker tag "${LOCAL_IMAGE}" "${ECR_IMAGE}"
docker push "${ECR_IMAGE}"

printf 'Pushed ECR image: %s\n' "${ECR_IMAGE}"
'@

Write-Utf8NoBom (Join-Path $scripts 'smoke_test_docker.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"
docker run --rm "${IMAGE_REF}" help
docker run --rm "${IMAGE_REF}" bash -lc 'bash --version >/dev/null && python --version && shellcheck --version | head -n 1'
'@

Write-Utf8NoBom (Join-Path $docs 'RUNNING_ON_HPC.md') @'
# Running Foundation Runner On HPC

## Build SIF From A Local Docker Image

```bash
cd /home/n.attallah/biodiscovery/00_container/foundation-runner
IMAGE_REF=biodiscoveryai/foundation-runner:0.3.0 bash scripts/build_apptainer_from_docker.sh
```

## Run B001

```bash
OUTPUT_ROOT=/home/n.attallah/biodiscovery/out \
SIF_PATH=foundation-runner_0.3.0.sif \
bash scripts/run_b001_apptainer.sh
```

## Run B002

```bash
OUTPUT_ROOT=/home/n.attallah/biodiscovery/out \
SIF_PATH=foundation-runner_0.3.0.sif \
bash scripts/run_b002_apptainer.sh
```
'@

Write-Utf8NoBom (Join-Path $docs 'RUNNING_ON_AWS.md') @'
# Running Foundation Runner On AWS

## Build Docker Image

```bash
cd /workspace/biodiscovery
docker build -f 00_container/foundation-runner/Dockerfile -t biodiscoveryai/foundation-runner:0.3.0 .
```

## Push To ECR

```bash
AWS_ACCOUNT_ID=<account_id> \
AWS_REGION=<region> \
bash 00_container/foundation-runner/scripts/push_ecr.sh
```

## Run B001 With Docker

```bash
OUTPUT_ROOT="$PWD/out" TARGET=aws bash 00_container/foundation-runner/scripts/run_b001_docker.sh
```

## Run B002 With Docker

```bash
OUTPUT_ROOT="$PWD/out" TARGET=aws bash 00_container/foundation-runner/scripts/run_b002_docker.sh
```
'@

Write-Utf8NoBom (Join-Path $base 'README.md') @'
# BioDiscoveryAI Foundation Runner Container

This directory defines the portable container used to run B001 foundation scripts
and B002 runtime implementation scripts consistently across local Docker, AWS
Docker/ECR, and HPC Apptainer/Singularity.

## What It Creates

| Artifact | Purpose | Importance |
|----------|---------|-----------:|
| Dockerfile | Builds the foundation-runner Docker image | 10 |
| requirements.txt | Python runtime dependencies for B002 skeletons | 9 |
| entrypoint.sh | Routes `b001` and `b002` commands inside the container | 10 |
| Apptainer.foundation-runner.def | HPC SIF build definition | 10 |
| scripts/build_docker.sh | Builds local Docker image | 10 |
| scripts/run_b001_docker.sh | Runs B001 inside Docker | 10 |
| scripts/run_b002_docker.sh | Runs B002 inside Docker | 10 |
| scripts/build_apptainer_from_docker.sh | Builds HPC SIF from Docker image | 10 |
| scripts/run_b001_apptainer.sh | Runs B001 inside Apptainer/Singularity | 10 |
| scripts/run_b002_apptainer.sh | Runs B002 inside Apptainer/Singularity | 10 |
| scripts/push_ecr.sh | Pushes image to AWS ECR | 9 |
| docs/RUNNING_ON_HPC.md | HPC operator instructions | 9 |
| docs/RUNNING_ON_AWS.md | AWS operator instructions | 9 |

## Build Docker

```bash
cd /path/to/biodiscovery
bash 00_container/foundation-runner/scripts/build_docker.sh
```

## Run B001

```bash
OUTPUT_ROOT="$PWD/out" bash 00_container/foundation-runner/scripts/run_b001_docker.sh
```

## Run B002

```bash
OUTPUT_ROOT="$PWD/out" bash 00_container/foundation-runner/scripts/run_b002_docker.sh
```

## Signing

Artifact signing is off by default to avoid blocking HPC and CI runs when keys
are not configured.

Enable real signing only when `cosign` or `gpg` keys are approved:

```bash
FOUNDATION_ENABLE_SIGNING=yes FOUNDATION_SIGNING_TIMEOUT_SECONDS=15 \
bash 00_container/foundation-runner/scripts/run_b001_docker.sh
```
'@

Write-Utf8NoBom (Join-Path $base 'CODEOWNERS') @'
# BioDiscoveryAI container assets
* @platform-owner @security-owner
Dockerfile @platform-owner @security-owner
Apptainer.foundation-runner.def @platform-owner @security-owner
scripts/* @platform-owner @security-owner
'@

$checksumPath = Join-Path $base 'checksums.txt'
$targets = Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object { $_.FullName -ne $checksumPath } | Sort-Object FullName
$lines = @()
foreach ($t in $targets) {
  $hash = (& 'C:\Program Files\Git\usr\bin\sha256sum.exe' $t.FullName 2>$null)
  if ($LASTEXITCODE -eq 0) { $lines += $hash }
}
[System.IO.File]::WriteAllLines($checksumPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Output "Container assets written: $base"
Write-Output "Checksums refreshed: $($lines.Count) entries"
