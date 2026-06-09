param(
    [string]$SourceRoot = "C:\biodiscovery\BDAI_Done\governance",
    [string]$CommittedBundleRoot = "$PSScriptRoot\..\governance_migration_bundle",
    [string]$WorkRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "bdai_governance_bundle_regression"),
    [switch]$SkipDockerValidation,
    [switch]$KeepWorkRoot
)

$ErrorActionPreference = "Stop"

function Get-RelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$BasePath,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $full = [System.IO.Path]::GetFullPath($Path)
    return $full.Substring($base.Length)
}

$source = [System.IO.Path]::GetFullPath($SourceRoot)
$committed = [System.IO.Path]::GetFullPath($CommittedBundleRoot)
$work = [System.IO.Path]::GetFullPath($WorkRoot)
$rebuilt = Join-Path $work "governance_migration_bundle"

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source root not found: $source"
}
if (-not (Test-Path -LiteralPath (Join-Path $committed "docker-compose.yml"))) {
    throw "Committed bundle root is missing docker-compose.yml: $committed"
}

if (Test-Path -LiteralPath $work) {
    $resolvedWork = [System.IO.Path]::GetFullPath($work)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedWork.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove non-temp regression work root: $resolvedWork"
    }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
Copy-Item -LiteralPath $committed -Destination $rebuilt -Recurse -Force

& "$PSScriptRoot\build_governance_migration_bundle.ps1" -SourceRoot $source -OutputRoot $rebuilt
if (-not $?) { throw "Bundle rebuild failed" }

$committedManifestRows = Import-Csv -LiteralPath (Join-Path $committed "manifest.csv")
$rebuiltManifestRows = Import-Csv -LiteralPath (Join-Path $rebuilt "manifest.csv")
$repoLocalRows = @($committedManifestRows | Where-Object { $_.domain -like "repo_local*" })
foreach ($row in $repoLocalRows) {
    $relative = $row.bundle_file -replace '/', [System.IO.Path]::DirectorySeparatorChar
    Copy-Item -LiteralPath (Join-Path $committed $relative) -Destination (Join-Path $rebuilt $relative) -Force
}

if ($repoLocalRows.Count -gt 0) {
    $rebuiltManifestRows = @($rebuiltManifestRows) + @($repoLocalRows)
    $rebuiltManifestRows |
        ConvertTo-Csv -NoTypeInformation |
        Set-Content -LiteralPath (Join-Path $rebuilt "manifest.csv") -Encoding UTF8
    $rebuiltManifestRows |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $rebuilt "manifest.json") -Encoding UTF8
}

& "$PSScriptRoot\lint_governance_migration_bundle.ps1" -BundleRoot $rebuilt
if (-not $?) { throw "Regression lint failed" }

$rebuiltManifest = Import-Csv -LiteralPath (Join-Path $rebuilt "manifest.csv")
foreach ($row in ($rebuiltManifest | Where-Object { $_.domain -notlike "repo_local*" })) {
    $relative = $row.bundle_file -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $committedPath = Join-Path $committed $relative
    $rebuiltPath = Join-Path $rebuilt $relative
    if (-not (Test-Path -LiteralPath $committedPath)) {
        throw "Committed bundle is missing source-generated file: $($row.bundle_file)"
    }
    $committedHash = (Get-FileHash -LiteralPath $committedPath -Algorithm SHA256).Hash
    $rebuiltHash = (Get-FileHash -LiteralPath $rebuiltPath -Algorithm SHA256).Hash
    if ($committedHash -ne $rebuiltHash) {
        throw "Source-generated file differs from committed bundle: $($row.bundle_file)"
    }
}

foreach ($relative in @("seeds/R__foundation_reference_seed.sql")) {
    $committedPath = Join-Path $committed ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $rebuiltPath = Join-Path $rebuilt ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $committedHash = (Get-FileHash -LiteralPath $committedPath -Algorithm SHA256).Hash
    $rebuiltHash = (Get-FileHash -LiteralPath $rebuiltPath -Algorithm SHA256).Hash
    if ($committedHash -ne $rebuiltHash) {
        throw "Source-generated seed differs from committed bundle: $relative"
    }
}

if (-not $SkipDockerValidation) {
    & "$PSScriptRoot\validate_governance_migration_bundle.ps1" -BundleRoot $rebuilt
    if (-not $?) { throw "Regression Docker validation failed" }
}

Write-Host "Governance migration regression PASS"
Write-Host "Rebuilt bundle: $rebuilt"

if (-not $KeepWorkRoot) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
