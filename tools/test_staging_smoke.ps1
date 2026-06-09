param(
    [string]$BaseUrl = $env:STAGING_GOVERNANCE_API_URL,
    [string]$BearerToken = $env:STAGING_GOVERNANCE_BEARER_TOKEN
)

$ErrorActionPreference = "Stop"

if (-not $BaseUrl -or -not $BearerToken) {
    Write-Host "Staging smoke test SKIPPED: STAGING_GOVERNANCE_API_URL and STAGING_GOVERNANCE_BEARER_TOKEN are not configured."
    exit 0
}

$base = $BaseUrl.TrimEnd("/")
$headers = @{ Authorization = "Bearer $BearerToken" }

$health = Invoke-RestMethod -Method Get -Uri "$base/health" -TimeoutSec 15
if ($health.status -ne "ok") {
    throw "Staging /health returned unexpected status"
}

$ready = Invoke-RestMethod -Method Get -Uri "$base/ready" -TimeoutSec 15
if ($ready.status -ne "ready") {
    throw "Staging /ready returned unexpected status"
}

$imageId = [guid]::NewGuid().ToString()
$deployable = Invoke-RestMethod -Method Get -Uri "$base/images/$imageId/deployable" -Headers $headers -TimeoutSec 15
if ($deployable.image_id -ne $imageId) {
    throw "Staging deployability response did not echo image_id"
}

Write-Host "Staging smoke test PASS"
