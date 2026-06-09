param(
    [string]$BundleRoot = "$PSScriptRoot\..\governance_migration_bundle",
    [int]$EventCount = 10000,
    [switch]$KeepRunning
)

$ErrorActionPreference = "Stop"

$bundle = [System.IO.Path]::GetFullPath($BundleRoot)
Push-Location $bundle
try {
    docker compose down -v
    if ($LASTEXITCODE -ne 0) { throw "docker compose down failed" }

    docker compose up -d postgres
    if ($LASTEXITCODE -ne 0) { throw "postgres startup failed" }

    docker compose run --rm flyway migrate
    if ($LASTEXITCODE -ne 0) { throw "flyway migrate failed" }

    $sql = @"
\set ON_ERROR_STOP on
\timing on
INSERT INTO evidence.execution_runs (
    run_id, script_id, module_id, target, status, actor, metadata
)
SELECT
    'perf-run-' || gs::text,
    'B001_01',
    'B001',
    'local',
    'PASS',
    'performance-baseline',
    jsonb_build_object('batch', 'baseline')
FROM generate_series(1, 100) gs;

INSERT INTO evidence.audit_events (
    run_id, event_type, status, message, actor, payload
)
SELECT
    'perf-run-' || (((gs - 1) % 100) + 1)::text,
    'performance_event',
    'completed',
    'baseline event',
    'performance-baseline',
    jsonb_build_object('sequence', gs)
FROM generate_series(1, $EventCount) gs;

EXPLAIN (ANALYZE, BUFFERS)
SELECT run_id, count(*)
FROM evidence.audit_events
WHERE created_at >= now() - interval '1 day'
GROUP BY run_id
ORDER BY count(*) DESC
LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS)
SELECT container_governance.is_image_deployable(gen_random_uuid());

EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM governance_admin.regulated_database_readiness
LIMIT 20;
"@

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "bdai_performance_baseline.sql"
    Set-Content -LiteralPath $tmp -Value $sql -Encoding UTF8
    docker compose cp $tmp postgres:/tmp/performance_baseline.sql
    if ($LASTEXITCODE -ne 0) { throw "performance SQL copy failed" }

    docker compose exec -T postgres psql -U bdai -d biodiscoveryai -f /tmp/performance_baseline.sql
    if ($LASTEXITCODE -ne 0) { throw "performance baseline failed" }

    Write-Host "Performance baseline PASS"
}
finally {
    if (-not $KeepRunning) {
        docker compose down -v
    }
    Pop-Location
}
