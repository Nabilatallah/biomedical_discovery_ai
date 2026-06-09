param(
    [string]$BundleRoot = "$PSScriptRoot\..\governance_migration_bundle",
    [string]$LogPath = "$PSScriptRoot\..\governance_migration_bundle\validation\last_flyway_validation.log"
)

$ErrorActionPreference = "Stop"

$log = [System.IO.Path]::GetFullPath($LogPath)
$logDir = Split-Path -Parent $log
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$stdout = "$log.stdout"
$stderr = "$log.stderr"
Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue

$childShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
$process = Start-Process -FilePath $childShell `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "$PSScriptRoot\validate_governance_migration_bundle.ps1",
        "-BundleRoot", $BundleRoot
    ) `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -NoNewWindow `
    -Wait `
    -PassThru

Get-Content -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue |
    Tee-Object -FilePath $log

if ($process.ExitCode -ne 0) {
    throw "Governance validation failed"
}

& "$PSScriptRoot\enforce_flyway_warning_registry.ps1" -LogPath $log
if (-not $?) {
    throw "Flyway warning registry enforcement failed"
}
