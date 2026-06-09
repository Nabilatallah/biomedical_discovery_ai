param(
    [string]$SourceRoot = "C:\biodiscovery\BDAI_Done\governance",
    [string]$OutputRoot = "$PSScriptRoot\..\governance_migration_bundle"
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

function Add-Migration {
    param(
        [Parameter(Mandatory=$true)][string]$SourceFile,
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string]$OriginalVersion,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $script:Sequence += 1
    $version = "{0:D3}" -f $script:Sequence
    $safeDescription = ($Description -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($safeDescription)) {
        $safeDescription = "migration"
    }

    $destName = "V$version" + "__" + $safeDescription + ".sql"
    $destPath = Join-Path $script:MigrationsDir $destName

    Copy-Item -LiteralPath $SourceFile -Destination $destPath -Force

    if ((Split-Path -Leaf $SourceFile) -eq "V015__container_governance_final_enterprise_standard.sql") {
        $text = Get-Content -LiteralPath $destPath -Raw
        $text = $text -replace '(?m)^CREATE TABLE container_governance\.', 'CREATE TABLE IF NOT EXISTS container_governance.'
        $text = $text -replace '(?m)^CREATE INDEX (idx_)', 'CREATE INDEX IF NOT EXISTS $1'
        $releaseCertifiedFunction = @'
CREATE TABLE IF NOT EXISTS container_governance.capa_records (
    capa_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capa_number              TEXT NOT NULL UNIQUE,
    related_entity_type      TEXT NOT NULL,
    related_entity_id        TEXT NOT NULL,
    severity                 TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status                   TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'closed', 'cancelled')),
    summary                  TEXT NOT NULL,
    corrective_action        TEXT,
    preventive_action        TEXT,
    owner                    TEXT NOT NULL DEFAULT current_user,
    opened_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_at                   TIMESTAMPTZ,
    closed_at                TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS container_governance.release_certifications (
    release_certification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_id                 UUID NOT NULL REFERENCES container_governance.container_images(image_id),
    certification_status     TEXT NOT NULL DEFAULT 'draft' CHECK (certification_status IN ('draft', 'pending', 'approved', 'certified', 'released', 'rejected', 'retired')),
    certification_version    TEXT NOT NULL DEFAULT '1.0.0',
    certified_by             TEXT,
    certified_at             TIMESTAMPTZ,
    release_notes            TEXT,
    evidence_summary         JSONB NOT NULL DEFAULT '{}',
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(image_id, certification_version)
);

CREATE OR REPLACE FUNCTION container_governance.is_release_certified(p_image_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM container_governance.release_certifications rc
        WHERE rc.image_id = p_image_id
          AND rc.certification_status IN ('approved', 'certified', 'released')
    )
    OR EXISTS (
        SELECT 1
        FROM container_governance.electronic_signatures es
        WHERE es.related_entity_type = 'container_image'
          AND es.related_entity_id = p_image_id::TEXT
          AND es.signature_meaning = 'release_authorization'
    );
$$;

'@
        $marker = "-- ============================================================================`r`n-- Final Consolidated Enterprise Readiness View"
        if ($text.Contains($marker)) {
            $text = $text.Replace($marker, $releaseCertifiedFunction + $marker)
        } else {
            $marker = "-- ============================================================================`n-- Final Consolidated Enterprise Readiness View"
            $text = $text.Replace($marker, $releaseCertifiedFunction + $marker)
        }
        Set-Content -LiteralPath $destPath -Value $text -Encoding UTF8
    }

    if ((Split-Path -Leaf $SourceFile) -eq "V098__evidence_ingestion_observability.sql") {
        $text = Get-Content -LiteralPath $destPath -Raw
        $text = $text.Replace(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_audit_events_idempotency_key ON evidence.audit_events(idempotency_key) WHERE idempotency_key IS NOT NULL;",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_audit_events_idempotency_key ON evidence.audit_events(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;"
        )
        $text = $text.Replace(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_execution_steps_idempotency_key ON evidence.execution_steps(idempotency_key) WHERE idempotency_key IS NOT NULL;",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_execution_steps_idempotency_key ON evidence.execution_steps(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;"
        )
        $text = $text.Replace(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_error_events_idempotency_key ON evidence.error_events(idempotency_key) WHERE idempotency_key IS NOT NULL;",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_error_events_idempotency_key ON evidence.error_events(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;"
        )
        $text = $text.Replace(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_artifacts_idempotency_key ON archive.artifacts(idempotency_key) WHERE idempotency_key IS NOT NULL;",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_artifacts_idempotency_key ON archive.artifacts(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;"
        )
        $text = $text.Replace(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_reports_idempotency_key ON reporting.execution_reports(idempotency_key) WHERE idempotency_key IS NOT NULL;",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_reports_idempotency_key ON reporting.execution_reports(idempotency_key, created_at) WHERE idempotency_key IS NOT NULL;"
        )
        Set-Content -LiteralPath $destPath -Value $text -Encoding UTF8
    }

    $script:ManifestRows += [pscustomobject]@{
        bundle_version = $version
        bundle_file = "migrations/$destName"
        source_version = $OriginalVersion
        domain = $Domain
        source_file = (Get-RelativePath -BasePath $script:SourceRootFull -Path $SourceFile) -replace '\\','/'
        bytes = (Get-Item -LiteralPath $SourceFile).Length
    }
}

function Add-OrderedFolder {
    param(
        [Parameter(Mandatory=$true)][string]$Folder,
        [Parameter(Mandatory=$true)][string]$Domain
    )

    Get-ChildItem -LiteralPath $Folder -File -Filter "*.sql" |
        Sort-Object Name |
        ForEach-Object {
            $name = $_.BaseName
            $originalVersion = if ($name -match '^(V?\d+)__?(.+)$') { $Matches[1].TrimStart('V') } else { $name }
            $description = if ($name -match '^(V?\d+)__?(.+)$') { $Matches[2] } else { $name -replace '^\d+_', '' }
            Add-Migration -SourceFile $_.FullName -Domain $Domain -OriginalVersion $originalVersion -Description $description
        }
}

function Add-ExplicitFiles {
    param(
        [Parameter(Mandatory=$true)][string]$BaseFolder,
        [Parameter(Mandatory=$true)][string[]]$FileNames,
        [Parameter(Mandatory=$true)][string]$Domain
    )

    foreach ($fileName in $FileNames) {
        $sourceFile = Join-Path $BaseFolder $fileName
        if (-not (Test-Path -LiteralPath $sourceFile)) {
            throw "Missing expected migration: $sourceFile"
        }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile)
        $originalVersion = if ($name -match '^V(\d+)__(.+)$') { $Matches[1] } else { $name }
        $description = if ($name -match '^V(\d+)__(.+)$') { $Matches[2] } else { $name }
        Add-Migration -SourceFile $sourceFile -Domain $Domain -OriginalVersion $originalVersion -Description $description
    }
}

$script:SourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
$outputFull = [System.IO.Path]::GetFullPath($OutputRoot)
$script:MigrationsDir = Join-Path $outputFull "migrations"
$seedsDir = Join-Path $outputFull "seeds"
$validationDir = Join-Path $outputFull "validation"

if (-not (Test-Path -LiteralPath $script:SourceRootFull)) {
    throw "Source root not found: $script:SourceRootFull"
}

New-Item -ItemType Directory -Path $outputFull -Force | Out-Null

foreach ($generatedPath in @($script:MigrationsDir, $seedsDir)) {
    if (Test-Path -LiteralPath $generatedPath) {
        Remove-Item -LiteralPath $generatedPath -Recurse -Force
    }
}

foreach ($generatedFile in @("manifest.csv", "manifest.json")) {
    $path = Join-Path $outputFull $generatedFile
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

New-Item -ItemType Directory -Path $script:MigrationsDir, $seedsDir, $validationDir -Force | Out-Null

$script:Sequence = 0
$script:ManifestRows = @()

Add-OrderedFolder `
    -Folder (Join-Path $script:SourceRootFull "v001_v010_environment_lineage\postgres\migrations") `
    -Domain "foundation_environment_lineage"

Add-ExplicitFiles `
    -BaseFolder (Join-Path $script:SourceRootFull "v011_v025_container_governance\postgres\migrations") `
    -Domain "container_governance" `
    -FileNames @(
        "V011__container_governance_registry.sql",
        "V015__container_governance_final_enterprise_standard.sql",
        "V016__container_governance_automation.sql",
        "V017__container_governance_ai_governance.sql",
        "V018__container_governance_federation.sql",
        "V019__container_governance_archive_partitioning.sql",
        "V020__container_governance_regulated_operations.sql",
        "V021__container_governance_policy_as_code.sql",
        "V022__container_governance_release_evidence_packets.sql",
        "V023__container_governance_revalidation_scheduler.sql",
        "V024__container_governance_incident_response.sql",
        "V025__container_governance_control_matrix.sql"
    )

Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v026_v038_ai_governance\postgres\migrations") -Domain "ai_governance"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v039_v048_ai_governance\postgres\migrations") -Domain "ai_governance_expansion"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v049_v057_ai_governance\postgres\migrations") -Domain "governance_domains"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v058_v063_foundation_kernel\postgres\migrations") -Domain "foundation_kernel"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v068_v074_platform_services\postgres\migrations") -Domain "platform_services"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v075_v084_platform_expansion\postgres\migrations") -Domain "platform_expansion"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v085_v090_implementation_contracts\postgres\migrations") -Domain "implementation_contracts"
Add-OrderedFolder -Folder (Join-Path $script:SourceRootFull "v091_v108_hardening_migrations") -Domain "hardening"

$seedSource = Join-Path $script:SourceRootFull "v001_v010_environment_lineage\postgres\seeds\001_seed_v10.sql"
Copy-Item -LiteralPath $seedSource -Destination (Join-Path $seedsDir "R__foundation_reference_seed.sql") -Force

$script:ManifestRows |
    ConvertTo-Csv -NoTypeInformation |
    Set-Content -LiteralPath (Join-Path $outputFull "manifest.csv") -Encoding UTF8

$script:ManifestRows |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $outputFull "manifest.json") -Encoding UTF8

Write-Host "Created governance migration bundle at $outputFull"
Write-Host "Versioned migrations: $($script:ManifestRows.Count)"
Write-Host "Repeatable seeds: 1"
