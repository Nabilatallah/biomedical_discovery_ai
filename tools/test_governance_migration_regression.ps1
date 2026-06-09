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

function Get-ComparableFiles {
    param([Parameter(Mandatory=$true)][string]$Root)

    $includeRoots = @(
        (Join-Path $Root "migrations"),
        (Join-Path $Root "seeds")
    )

    $files = foreach ($path in $includeRoots) {
        Get-ChildItem -LiteralPath $path -File -Recurse
    }

    $files += Get-Item -LiteralPath (Join-Path $Root "manifest.csv")
    $files += Get-Item -LiteralPath (Join-Path $Root "manifest.json")

    $files |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                RelativePath = (Get-RelativePath -BasePath $Root -Path $_.FullName) -replace '\\','/'
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
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

& "$PSScriptRoot\lint_governance_migration_bundle.ps1" -BundleRoot $rebuilt
if (-not $?) { throw "Regression lint failed" }

$committedFiles = Get-ComparableFiles -Root $committed
$rebuiltFiles = Get-ComparableFiles -Root $rebuilt
$diff = Compare-Object -ReferenceObject $committedFiles -DifferenceObject $rebuiltFiles -Property RelativePath, Hash
if ($diff) {
    $diff | Format-Table -AutoSize | Out-String | Write-Error
    throw "Rebuilt bundle differs from committed bundle"
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
