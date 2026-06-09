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
    if ($LASTEXITCODE -ne 0) { throw "docker compose down failed with exit code $LASTEXITCODE" }

    docker compose up -d postgres
    if ($LASTEXITCODE -ne 0) { throw "docker compose up failed with exit code $LASTEXITCODE" }

    docker compose run --rm flyway migrate
    if ($LASTEXITCODE -ne 0) { throw "flyway migrate failed with exit code $LASTEXITCODE" }

    docker compose exec -T postgres psql -U bdai -d biodiscoveryai -f /validation/validate_schema.sql
    if ($LASTEXITCODE -ne 0) { throw "schema validation failed with exit code $LASTEXITCODE" }

    docker compose run --rm governance-validator
    if ($LASTEXITCODE -ne 0) { throw "python governance validation failed with exit code $LASTEXITCODE" }

    docker compose up -d governance-api
    if ($LASTEXITCODE -ne 0) { throw "governance-api startup failed with exit code $LASTEXITCODE" }

    $ready = $false
    for ($i = 1; $i -le 30; $i++) {
        docker compose exec -T governance-api python -c "import socket, sys; s=socket.socket(); s.settimeout(3); sys.exit(s.connect_ex(('127.0.0.1', 8000)))" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw "governance-api readiness check failed after 60 seconds" }

    docker compose exec -T governance-api python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/ready', timeout=5).read().decode())"
    if ($LASTEXITCODE -ne 0) { throw "governance-api readiness endpoint failed with exit code $LASTEXITCODE" }
}
finally {
    if (-not $KeepRunning) {
        docker compose down -v
    }
    Pop-Location
}
