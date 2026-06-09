param(
    [string]$Repository = $(if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { "Nabilatallah/biomedical_discovery_ai" }),
    [string]$Branch = "main",
    [string]$Token = $env:GITHUB_TOKEN
)

$ErrorActionPreference = "Stop"

if (-not $Token) {
    throw "GITHUB_TOKEN with repository administration permission is required to apply branch protection"
}

$headers = @{
    Authorization = "Bearer $Token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$body = [ordered]@{
    required_status_checks = [ordered]@{
        strict = $true
        contexts = @("validate")
    }
    enforce_admins = $true
    required_pull_request_reviews = [ordered]@{
        required_approving_review_count = 1
        dismiss_stale_reviews = $true
        require_code_owner_reviews = $false
        require_last_push_approval = $true
    }
    restrictions = $null
    required_conversation_resolution = $true
    allow_force_pushes = $false
    allow_deletions = $false
}

$uri = "https://api.github.com/repos/$Repository/branches/$Branch/protection"
Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body ($body | ConvertTo-Json -Depth 6) -ContentType "application/json" | Out-Null
Write-Host "Branch protection applied to $Repository/$Branch"
