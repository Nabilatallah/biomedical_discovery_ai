param(
    [string]$BundleRoot = "$PSScriptRoot\..\governance_migration_bundle",
    [string]$OutputPath = "$PSScriptRoot\..\governance_migration_bundle\validation\release_evidence_packet.json",
    [switch]$RunValidation
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$bundle = [System.IO.Path]::GetFullPath($BundleRoot)
$out = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null

if ($RunValidation) {
    & "$PSScriptRoot\validate_governance_with_warning_registry.ps1" -BundleRoot $bundle
    if (-not $?) { throw "Release evidence validation failed" }
}

$migrationFiles = Get-ChildItem -LiteralPath (Join-Path $bundle "migrations") -File -Filter "V*.sql" | Sort-Object Name
$manifestPath = Join-Path $bundle "manifest.json"
$flywayLog = Join-Path $bundle "validation\last_flyway_validation.log"

$packet = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    git_commit = (git -C $repoRoot rev-parse HEAD)
    git_status_short = (git -C $repoRoot status --short)
    migration_count = $migrationFiles.Count
    latest_migration = $migrationFiles[-1].Name
    manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    migration_chain_sha256 = (
        $migrationFiles |
            ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } |
            Out-String
    ).Trim() | ForEach-Object {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($_)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
    }
    validation_log = $flywayLog
    validation_log_sha256 = if (Test-Path -LiteralPath $flywayLog) { (Get-FileHash -LiteralPath $flywayLog -Algorithm SHA256).Hash } else { $null }
    docker_images = @(
        "postgres:16",
        "flyway/flyway:10",
        "governance-api:local-build"
    )
    controls = [ordered]@{
        static_lint = "tools/lint_governance_migration_bundle.ps1"
        runtime_validation = "tools/validate_governance_with_warning_registry.ps1"
        backup_restore = "tools/test_backup_restore_drill.ps1"
        performance_baseline = "tools/run_performance_baseline.ps1"
        api_contracts = "governance_migration_bundle/apps/governance-api/tests"
        warning_registry = "docs/FLYWAY_WARNING_REGISTRY.md"
    }
}

$packet | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "Release evidence packet: $out"
