param(
    [string]$OutputDir = "$PSScriptRoot\..\governance_migration_bundle\validation\supply_chain",
    [string[]]$DockerImages = @("postgres:16", "flyway/flyway:10", "governance-api:local-build")
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$out = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $out -Force | Out-Null

$files = git -C $repoRoot ls-files | ForEach-Object {
    $path = Join-Path $repoRoot $_
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -ne $item -and -not $item.PSIsContainer) {
        [ordered]@{
            path = $_
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            size_bytes = $item.Length
        }
    }
}

$images = foreach ($image in $DockerImages) {
    $inspect = $null
    try {
        $inspect = & docker image inspect $image 2>$null
        $imageExitCode = $LASTEXITCODE
    }
    catch {
        $imageExitCode = 1
    }
    if ($imageExitCode -eq 0 -and $inspect) {
        $meta = $inspect | ConvertFrom-Json
        [ordered]@{
            image = $image
            id = $meta[0].Id
            repo_digests = @($meta[0].RepoDigests)
            created = $meta[0].Created
        }
    }
    else {
        [ordered]@{
            image = $image
            id = $null
            repo_digests = @()
            created = $null
        }
    }
}

$sbom = [ordered]@{
    bom_format = "CycloneDX-like"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    git_commit = (git -C $repoRoot rev-parse HEAD)
    components = $files
    docker_images = $images
}

$sbomPath = Join-Path $out "sbom.json"
$sbom | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sbomPath -Encoding UTF8

$sbomHash = (Get-FileHash -LiteralPath $sbomPath -Algorithm SHA256).Hash
$provenance = [ordered]@{
    predicate_type = "https://slsa.dev/provenance/v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    subject = [ordered]@{
        name = "biomedical_discovery_ai"
        digest = [ordered]@{ sha256 = $sbomHash }
    }
    builder = [ordered]@{
        id = if ($env:GITHUB_ACTIONS -eq "true") { "github-actions" } else { "local" }
        run_id = $env:GITHUB_RUN_ID
        run_attempt = $env:GITHUB_RUN_ATTEMPT
    }
    materials = @(
        [ordered]@{
            uri = if ($env:GITHUB_SERVER_URL) { "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY" } else { $repoRoot }
            digest = [ordered]@{ gitCommit = (git -C $repoRoot rev-parse HEAD) }
        }
    )
}

$provenancePath = Join-Path $out "provenance.json"
$provenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $provenancePath -Encoding UTF8

Write-Host "SBOM: $sbomPath"
Write-Host "Provenance: $provenancePath"
