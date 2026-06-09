$root = 'C:\biodiscovery'
$base = Join-Path $root '00_orchestration\nextflow\b001_apptainer'
$scripts = Join-Path $base 'scripts'
$docs = Join-Path $base 'docs'
New-Item -ItemType Directory -Force -Path $base, $scripts, $docs | Out-Null

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
}

Write-Utf8NoBom (Join-Path $base 'main.nf') @'
nextflow.enable.dsl = 2

/*
 * BioDiscoveryAI B001 Foundation Automation
 * Nextflow + Apptainer wrapper around b001_40_foundation_orchestrator.sh.
 *
 * The B001 scripts remain the source of truth for generated project artifacts.
 * This pipeline is the execution control plane for HPC/AWS/local reproducibility.
 */

params.project_name = params.project_name ?: 'biodiscoveryai'
params.target = params.target ?: 'hpc'
params.container_runtime = params.container_runtime ?: 'apptainer'
params.output_root = params.output_root ?: "${launchDir}/out"
params.image_ref = params.image_ref ?: 'biodiscoveryai/foundation-runner:0.3.0'
params.container = params.container ?: 'docker://biodiscoveryai/foundation-runner:0.3.0'
params.from_step = params.from_step ?: '01'
params.to_step = params.to_step ?: '39'
params.only = params.only ?: ''
params.skip = params.skip ?: ''
params.include_common = params.include_common ?: false
params.continue_on_failure = params.continue_on_failure ?: false
params.dry_run = params.dry_run ?: false
params.quiet = params.quiet ?: false
params.enable_signing = params.enable_signing ?: false
params.signing_timeout_seconds = params.signing_timeout_seconds ?: 15

process RUN_B001_FOUNDATION {
    tag "${params.project_name}"
    label 'b001_foundation'

    container "${params.container}"

    publishDir "${params.output_root}/${params.project_name}/.nextflow/b001",
        mode: 'copy',
        overwrite: true,
        pattern: 'nextflow_b001_*'

    output:
    path 'nextflow_b001_summary.json', emit: summary
    path 'nextflow_b001_report.md', emit: report

    script:
    def includeCommon = params.include_common ? '--include-common' : ''
    def continueOnFailure = params.continue_on_failure ? '--continue-on-failure' : ''
    def dryRun = params.dry_run ? '--dry-run' : ''
    def quiet = params.quiet ? '--quiet' : ''
    def onlyArg = params.only ? "--only \"${params.only}\"" : ''
    def skipArg = params.skip ? "--skip \"${params.skip}\"" : ''
    def signingEnabled = params.enable_signing ? 'yes' : 'no'
    """
    set -Eeuo pipefail

    mkdir -p "${params.output_root}"

    started_at="\$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    set +e
    FOUNDATION_ENABLE_SIGNING="${signingEnabled}" \\
    FOUNDATION_SIGNING_TIMEOUT_SECONDS="${params.signing_timeout_seconds}" \\
    /usr/local/bin/bdai-entrypoint b001 \\
      --project-name "${params.project_name}" \\
      --target "${params.target}" \\
      --container-runtime "${params.container_runtime}" \\
      --output-root "${params.output_root}" \\
      --image "${params.image_ref}" \\
      --from "${params.from_step}" \\
      --to "${params.to_step}" \\
      ${onlyArg} \\
      ${skipArg} \\
      ${includeCommon} \\
      ${continueOnFailure} \\
      ${dryRun} \\
      ${quiet}
    exit_code="\$?"
    set -e

    ended_at="\$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    project_root="${params.output_root}/${params.project_name}"
    b001_report="\${project_root}/.foundation/foundation_orchestrator/report.md"

    cat > nextflow_b001_summary.json <<EOF
    {
      "pipeline": "b001_nextflow_apptainer",
      "project_name": "${params.project_name}",
      "target": "${params.target}",
      "container_runtime": "${params.container_runtime}",
      "container": "${params.container}",
      "image_ref": "${params.image_ref}",
      "output_root": "${params.output_root}",
      "project_root": "\${project_root}",
      "b001_report": "\${b001_report}",
      "started_at": "\${started_at}",
      "ended_at": "\${ended_at}",
      "exit_code": "\${exit_code}"
    }
EOF

    cat > nextflow_b001_report.md <<EOF
    # B001 Nextflow + Apptainer Execution Report

    | Field | Value |
    |-------|-------|
    | Pipeline | b001_nextflow_apptainer |
    | Project | ${params.project_name} |
    | Target | ${params.target} |
    | Container runtime | ${params.container_runtime} |
    | Container | ${params.container} |
    | Image reference | ${params.image_ref} |
    | Output root | ${params.output_root} |
    | Project root | \${project_root} |
    | B001 report | \${b001_report} |
    | Started at | \${started_at} |
    | Ended at | \${ended_at} |
    | Exit code | \${exit_code} |

    ## Notes

    Nextflow launched the B001 foundation orchestrator inside the configured
    Apptainer container. The B001 report remains the canonical foundation report.
EOF

    exit "\${exit_code}"
    """
}

workflow {
    RUN_B001_FOUNDATION()
}
'@

Write-Utf8NoBom (Join-Path $base 'nextflow.config') @'
/*
 * BioDiscoveryAI B001 Nextflow + Apptainer configuration.
 */

params {
  project_name = 'biodiscoveryai'
  target = 'hpc'
  container_runtime = 'apptainer'
  output_root = "${launchDir}/out"
  work_dir = "${launchDir}/work"
  image_ref = 'biodiscoveryai/foundation-runner:0.3.0'
  container = 'docker://biodiscoveryai/foundation-runner:0.3.0'
  from_step = '01'
  to_step = '39'
  only = ''
  skip = ''
  include_common = false
  continue_on_failure = false
  dry_run = false
  quiet = false
  enable_signing = false
  signing_timeout_seconds = 15
}

workDir = params.work_dir

process {
  errorStrategy = 'terminate'
  maxRetries = 0
  shell = ['/bin/bash', '-euo', 'pipefail']

  withLabel: b001_foundation {
    cpus = 2
    memory = '4 GB'
    time = '1h'
    container = params.container
    containerOptions = "--bind ${params.output_root}:${params.output_root}"
  }
}

apptainer {
  enabled = true
  autoMounts = true
  cacheDir = "${launchDir}/.apptainer-cache"
}

singularity {
  enabled = false
}

profiles {
  hpc {
    process.executor = 'slurm'
    apptainer.enabled = true
    apptainer.autoMounts = true
    params.target = 'hpc'
    params.container_runtime = 'apptainer'
  }

  local_apptainer {
    process.executor = 'local'
    apptainer.enabled = true
    apptainer.autoMounts = true
    params.target = 'hpc'
    params.container_runtime = 'apptainer'
  }

  local_dryrun {
    process.executor = 'local'
    apptainer.enabled = false
    process.container = null
    params.target = 'local'
    params.container_runtime = 'none'
    params.dry_run = true
  }
}
'@

Write-Utf8NoBom (Join-Path $base 'params.example.json') @'
{
  "project_name": "biodiscoveryai",
  "target": "hpc",
  "container_runtime": "apptainer",
  "output_root": "/home/n.attallah/biodiscovery",
  "work_dir": "/home/n.attallah/biodiscovery/work",
  "container": "docker://biodiscoveryai/foundation-runner:0.3.0",
  "image_ref": "biodiscoveryai/foundation-runner:0.3.0",
  "from_step": "01",
  "to_step": "39",
  "include_common": false,
  "continue_on_failure": false,
  "enable_signing": false,
  "signing_timeout_seconds": 15
}
'@

Write-Utf8NoBom (Join-Path $scripts 'validate_prereqs.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

missing=0
for cmd in nextflow java; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf '[MISSING] %s\n' "${cmd}" >&2
    missing=1
  else
    printf '[OK] %s: %s\n' "${cmd}" "$(${cmd} -version 2>&1 | head -n 1)"
  fi
done

if command -v apptainer >/dev/null 2>&1; then
  printf '[OK] apptainer: %s\n' "$(apptainer --version 2>&1 | head -n 1)"
elif command -v singularity >/dev/null 2>&1; then
  printf '[OK] singularity: %s\n' "$(singularity --version 2>&1 | head -n 1)"
else
  printf '[MISSING] apptainer or singularity\n' >&2
  missing=1
fi

exit "${missing}"
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b001_nextflow_apptainer.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${PIPELINE_DIR}/../../.." && pwd)"

PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
OUTPUT_ROOT="${OUTPUT_ROOT:-${PROJECT_ROOT}}"
WORK_DIR="${WORK_DIR:-${PROJECT_ROOT}/work}"
CONTAINER="${CONTAINER:-docker://biodiscoveryai/foundation-runner:0.3.0}"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"

mkdir -p "${OUTPUT_ROOT}" "${WORK_DIR}"

nextflow run "${PIPELINE_DIR}/main.nf" \
  -profile local_apptainer \
  -work-dir "${WORK_DIR}" \
  --project_name "${PROJECT_NAME}" \
  --output_root "${OUTPUT_ROOT}" \
  --work_dir "${WORK_DIR}" \
  --container "${CONTAINER}" \
  --image_ref "${IMAGE_REF}" \
  "$@"
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b001_nextflow_hpc_slurm.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${PIPELINE_DIR}/../../.." && pwd)"

PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
OUTPUT_ROOT="${OUTPUT_ROOT:-${PROJECT_ROOT}}"
WORK_DIR="${WORK_DIR:-${PROJECT_ROOT}/work}"
CONTAINER="${CONTAINER:-docker://biodiscoveryai/foundation-runner:0.3.0}"
IMAGE_REF="${IMAGE_REF:-biodiscoveryai/foundation-runner:0.3.0}"

mkdir -p "${OUTPUT_ROOT}" "${WORK_DIR}"

nextflow run "${PIPELINE_DIR}/main.nf" \
  -profile hpc \
  -work-dir "${WORK_DIR}" \
  --project_name "${PROJECT_NAME}" \
  --output_root "${OUTPUT_ROOT}" \
  --work_dir "${WORK_DIR}" \
  --container "${CONTAINER}" \
  --image_ref "${IMAGE_REF}" \
  "$@"
'@

Write-Utf8NoBom (Join-Path $scripts 'run_b001_nextflow_local_dryrun.sh') @'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${PIPELINE_DIR}/../../.." && pwd)"

PROJECT_NAME="${PROJECT_NAME:-biodiscoveryai}"
OUTPUT_ROOT="${OUTPUT_ROOT:-${PROJECT_ROOT}/dryrun-out}"
WORK_DIR="${WORK_DIR:-${PROJECT_ROOT}/dryrun-work}"

mkdir -p "${OUTPUT_ROOT}" "${WORK_DIR}"

nextflow run "${PIPELINE_DIR}/main.nf" \
  -profile local_dryrun \
  -work-dir "${WORK_DIR}" \
  --project_name "${PROJECT_NAME}" \
  --output_root "${OUTPUT_ROOT}" \
  --work_dir "${WORK_DIR}" \
  "$@"
'@

Write-Utf8NoBom (Join-Path $scripts 'submit_b001_nextflow.slurm') @'
#!/bin/bash
#SBATCH --job-name=bdai-b001-nextflow
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --output=b001-nextflow-%j.out
#SBATCH --error=b001-nextflow-%j.err

set -Eeuo pipefail

cd "${SLURM_SUBMIT_DIR:-$PWD}"

OUTPUT_ROOT="${OUTPUT_ROOT:-/home/n.attallah/biodiscovery}" \
WORK_DIR="${WORK_DIR:-/home/n.attallah/biodiscovery/work}" \
bash 00_orchestration/nextflow/b001_apptainer/scripts/run_b001_nextflow_hpc_slurm.sh
'@

Write-Utf8NoBom (Join-Path $docs 'RUNNING_B001_NEXTFLOW_APPTAINER.md') @'
# B001 Automation With Nextflow + Apptainer

This pipeline runs `b001_40_foundation_orchestrator.sh` inside the
`foundation-runner` container using Nextflow as the workflow control plane and
Apptainer as the HPC container runtime.

## What It Automates

| Layer | Role |
|------|------|
| Nextflow | Submits and tracks the B001 orchestration job |
| Apptainer | Provides the reproducible container runtime on HPC |
| foundation-runner | Supplies Bash, Python, shellcheck, bats, and B001/B002 scripts |
| B001 orchestrator | Generates the foundation substrate and audit evidence |

## Validate Prerequisites

```bash
cd /home/n.attallah/biodiscovery
bash 00_orchestration/nextflow/b001_apptainer/scripts/validate_prereqs.sh
```

## Run On An HPC Login Node With Local Executor

Use this for a small first test:

```bash
cd /home/n.attallah/biodiscovery
OUTPUT_ROOT=/home/n.attallah/biodiscovery \
WORK_DIR=/home/n.attallah/biodiscovery/work \
bash 00_orchestration/nextflow/b001_apptainer/scripts/run_b001_nextflow_apptainer.sh
```

## Run Through Slurm

```bash
cd /home/n.attallah/biodiscovery
sbatch 00_orchestration/nextflow/b001_apptainer/scripts/submit_b001_nextflow.slurm
```

## Use A Local SIF Instead Of Docker Pull

```bash
CONTAINER=/home/n.attallah/biodiscovery/00_container/foundation-runner/foundation-runner_0.3.0.sif \
bash 00_orchestration/nextflow/b001_apptainer/scripts/run_b001_nextflow_apptainer.sh
```

## Resume From A Failed B001 Step

```bash
bash 00_orchestration/nextflow/b001_apptainer/scripts/run_b001_nextflow_apptainer.sh --from_step 09
```

## Enable Real Signing

```bash
bash 00_orchestration/nextflow/b001_apptainer/scripts/run_b001_nextflow_apptainer.sh \
  --enable_signing true \
  --signing_timeout_seconds 15
```

## Reports

| Report | Purpose |
|--------|---------|
| `<output_root>/biodiscoveryai/.foundation/foundation_orchestrator/report.md` | Canonical B001 report |
| `<output_root>/biodiscoveryai/.nextflow/b001/nextflow_b001_report.md` | Nextflow execution report |
| `<output_root>/biodiscoveryai/.nextflow/b001/nextflow_b001_summary.json` | Machine-readable Nextflow summary |
'@

Write-Utf8NoBom (Join-Path $base 'README.md') @'
# BioDiscoveryAI B001 Nextflow + Apptainer Automation

This directory combines Nextflow, Apptainer, and the B001 foundation
orchestrator so one workflow can generate the complete foundation substrate on
HPC with containerized reproducibility.

## Main Files

| File | Purpose | Importance |
|------|---------|-----------:|
| `main.nf` | Nextflow pipeline that runs B001 inside the runner container | 10 |
| `nextflow.config` | HPC/local Apptainer profiles and runtime parameters | 10 |
| `params.example.json` | Example parameter contract | 8 |
| `scripts/validate_prereqs.sh` | Checks Nextflow, Java, and Apptainer/Singularity | 9 |
| `scripts/run_b001_nextflow_apptainer.sh` | Local executor + Apptainer test run | 10 |
| `scripts/run_b001_nextflow_hpc_slurm.sh` | Slurm executor + Apptainer run | 10 |
| `scripts/submit_b001_nextflow.slurm` | Submit wrapper for HPC | 10 |
| `docs/RUNNING_B001_NEXTFLOW_APPTAINER.md` | Operator instructions | 9 |

## Quick Start

```bash
cd /home/n.attallah/biodiscovery
bash 00_orchestration/nextflow/b001_apptainer/scripts/validate_prereqs.sh
bash 00_orchestration/nextflow/b001_apptainer/scripts/run_b001_nextflow_apptainer.sh
```
'@

Write-Utf8NoBom (Join-Path $base 'CODEOWNERS') @'
# BioDiscoveryAI Nextflow orchestration assets
* @platform-owner @security-owner
main.nf @platform-owner @security-owner
nextflow.config @platform-owner @security-owner
scripts/* @platform-owner @security-owner
'@

Write-Utf8NoBom (Join-Path $base '.gitignore') @'
.nextflow*
work/
dryrun-work/
dryrun-out/
.apptainer-cache/
*.log
*.trace
timeline.html
report.html
dag.html
'@

$checksumPath = Join-Path $base 'checksums.txt'
$targets = Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object { $_.FullName -ne $checksumPath } | Sort-Object FullName
$lines = @()
foreach ($t in $targets) {
  $hash = (& 'C:\Program Files\Git\usr\bin\sha256sum.exe' $t.FullName 2>$null)
  if ($LASTEXITCODE -eq 0) { $lines += $hash }
}
[System.IO.File]::WriteAllLines($checksumPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Output "B001 Nextflow + Apptainer assets written: $base"
Write-Output "Checksums refreshed: $($lines.Count) entries"
