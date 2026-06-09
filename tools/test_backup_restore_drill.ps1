param(
    [string]$BundleRoot = "$PSScriptRoot\..\governance_migration_bundle",
    [switch]$KeepRunning
)

$ErrorActionPreference = "Stop"

$bundle = [System.IO.Path]::GetFullPath($BundleRoot)
if (-not (Test-Path -LiteralPath (Join-Path $bundle "docker-compose.yml"))) {
    throw "Missing docker-compose.yml in $bundle"
}

Push-Location $bundle
try {
    docker compose down -v
    if ($LASTEXITCODE -ne 0) { throw "docker compose down failed" }

    docker compose up -d postgres
    if ($LASTEXITCODE -ne 0) { throw "postgres startup failed" }

    docker compose run --rm flyway migrate
    if ($LASTEXITCODE -ne 0) { throw "flyway migrate failed" }

    docker compose exec -T postgres pg_dump -U bdai -d biodiscoveryai -Fc -f /tmp/bdai_governance.dump
    if ($LASTEXITCODE -ne 0) { throw "pg_dump failed" }

    docker compose exec -T postgres createdb -U bdai biodiscoveryai_restore
    if ($LASTEXITCODE -ne 0) { throw "restore database creation failed" }

    docker compose exec -T postgres pg_restore -U bdai -d biodiscoveryai_restore /tmp/bdai_governance.dump
    if ($LASTEXITCODE -ne 0) { throw "pg_restore failed" }

    docker compose exec -T postgres psql -U bdai -d biodiscoveryai_restore -f /validation/validate_schema.sql
    if ($LASTEXITCODE -ne 0) { throw "restored database validation failed" }

    Write-Host "Backup/restore drill PASS"
}
finally {
    if (-not $KeepRunning) {
        docker compose down -v
    }
    Pop-Location
}
