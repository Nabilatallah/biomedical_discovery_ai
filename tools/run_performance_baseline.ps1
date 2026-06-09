param(
    [string]$BundleRoot = "$PSScriptRoot\..\governance_migration_bundle",
    [int]$EventCount = 10000,
    [int]$MaxRunInsertMs = 5000,
    [int]$MaxAuditInsertMs = 10000,
    [int]$MaxAuditQueryMs = 5000,
    [int]$MaxDeployabilityQueryMs = 3000,
    [int]$MaxReadinessViewMs = 10000,
    [int]$MaxTotalSeconds = 180,
    [switch]$KeepRunning
)

$ErrorActionPreference = "Stop"

$bundle = [System.IO.Path]::GetFullPath($BundleRoot)
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
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

CREATE TEMP TABLE performance_thresholds (
    name text PRIMARY KEY,
    elapsed_ms numeric NOT NULL,
    max_ms numeric NOT NULL
);

DO `$`$
DECLARE
    started_at timestamptz;
    elapsed numeric;
BEGIN
    started_at := clock_timestamp();
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
    elapsed := extract(epoch from clock_timestamp() - started_at) * 1000;
    INSERT INTO performance_thresholds VALUES ('execution_run_ingestion', elapsed, $MaxRunInsertMs);
    IF elapsed > $MaxRunInsertMs THEN
        RAISE EXCEPTION 'execution_run_ingestion exceeded threshold: % ms > % ms', elapsed, $MaxRunInsertMs;
    END IF;

    started_at := clock_timestamp();
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
    elapsed := extract(epoch from clock_timestamp() - started_at) * 1000;
    INSERT INTO performance_thresholds VALUES ('audit_event_writes', elapsed, $MaxAuditInsertMs);
    IF elapsed > $MaxAuditInsertMs THEN
        RAISE EXCEPTION 'audit_event_writes exceeded threshold: % ms > % ms', elapsed, $MaxAuditInsertMs;
    END IF;
END
`$`$;

DO `$`$
DECLARE
    started_at timestamptz;
    elapsed numeric;
BEGIN
    started_at := clock_timestamp();
    PERFORM run_id, count(*)
    FROM evidence.audit_events
    WHERE created_at >= now() - interval '1 day'
    GROUP BY run_id
    ORDER BY count(*) DESC
    LIMIT 10;
    elapsed := extract(epoch from clock_timestamp() - started_at) * 1000;
    INSERT INTO performance_thresholds VALUES ('audit_partition_query', elapsed, $MaxAuditQueryMs);
    IF elapsed > $MaxAuditQueryMs THEN
        RAISE EXCEPTION 'audit_partition_query exceeded threshold: % ms > % ms', elapsed, $MaxAuditQueryMs;
    END IF;

    started_at := clock_timestamp();
    PERFORM container_governance.is_image_deployable(gen_random_uuid());
    elapsed := extract(epoch from clock_timestamp() - started_at) * 1000;
    INSERT INTO performance_thresholds VALUES ('deployability_query', elapsed, $MaxDeployabilityQueryMs);
    IF elapsed > $MaxDeployabilityQueryMs THEN
        RAISE EXCEPTION 'deployability_query exceeded threshold: % ms > % ms', elapsed, $MaxDeployabilityQueryMs;
    END IF;

    started_at := clock_timestamp();
    PERFORM *
    FROM governance_admin.regulated_database_readiness
    LIMIT 20;
    elapsed := extract(epoch from clock_timestamp() - started_at) * 1000;
    INSERT INTO performance_thresholds VALUES ('readiness_view_query', elapsed, $MaxReadinessViewMs);
    IF elapsed > $MaxReadinessViewMs THEN
        RAISE EXCEPTION 'readiness_view_query exceeded threshold: % ms > % ms', elapsed, $MaxReadinessViewMs;
    END IF;
END
`$`$;

TABLE performance_thresholds
ORDER BY name;

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

    $totalTimer.Stop()
    if ($totalTimer.Elapsed.TotalSeconds -gt $MaxTotalSeconds) {
        throw "performance baseline total runtime exceeded threshold: $([math]::Round($totalTimer.Elapsed.TotalSeconds, 2))s > ${MaxTotalSeconds}s"
    }
    Write-Host "Performance baseline PASS"
}
finally {
    if (-not $KeepRunning) {
        docker compose down -v
    }
    Pop-Location
}
