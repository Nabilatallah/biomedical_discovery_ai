param(
    [string]$BundleRoot = "$PSScriptRoot\..\governance_migration_bundle"
)

$ErrorActionPreference = "Stop"

$bundle = [System.IO.Path]::GetFullPath($BundleRoot)
$migrationsDir = Join-Path $bundle "migrations"
$manifestPath = Join-Path $bundle "manifest.csv"
$seedPath = Join-Path $bundle "seeds\R__foundation_reference_seed.sql"

if (-not (Test-Path -LiteralPath $migrationsDir)) {
    throw "Missing migrations directory: $migrationsDir"
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing manifest: $manifestPath"
}
if (-not (Test-Path -LiteralPath $seedPath)) {
    throw "Missing repeatable seed: $seedPath"
}

$files = Get-ChildItem -LiteralPath $migrationsDir -File -Filter "V*.sql" | Sort-Object Name
if ($files.Count -eq 0) {
    throw "No migration files found in $migrationsDir"
}

$seen = @{}
for ($i = 0; $i -lt $files.Count; $i++) {
    $file = $files[$i]
    if ($file.Name -notmatch '^V(\d{3})__[a-z0-9_]+\.sql$') {
        throw "Invalid migration filename: $($file.Name)"
    }

    $version = [int]$Matches[1]
    $expected = $i + 1
    if ($version -ne $expected) {
        throw "Migration sequence gap: expected V$('{0:D3}' -f $expected), found $($file.Name)"
    }

    if ($seen.ContainsKey($file.Name)) {
        throw "Duplicate migration filename: $($file.Name)"
    }
    $seen[$file.Name] = $true
}

$manifest = Import-Csv -LiteralPath $manifestPath
if ($manifest.Count -ne $files.Count) {
    throw "Manifest count $($manifest.Count) does not match migration count $($files.Count)"
}

foreach ($row in $manifest) {
    $path = Join-Path $bundle ($row.bundle_file -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Manifest references missing file: $($row.bundle_file)"
    }
}

Write-Host "Governance bundle lint PASS"
Write-Host "Migrations: $($files.Count)"
Write-Host "Seed: $seedPath"
