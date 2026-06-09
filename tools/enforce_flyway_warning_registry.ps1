param(
    [Parameter(Mandatory=$true)][string]$LogPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "Validation log not found: $LogPath"
}

$allowed = @(
    'extension "pgcrypto" already exists, skipping',
    'schema ".+" already exists, skipping',
    'relation ".+" already exists, skipping',
    'trigger ".+" does not exist, skipping',
    'constraint ".+" does not exist, skipping',
    'policy ".+" does not exist, skipping',
    'event trigger ".+" does not exist, skipping',
    'there is already a transaction in progress'
)

$unexpected = @()
Get-Content -LiteralPath $LogPath | ForEach-Object {
    $line = $_
    if ($line -match '^(WARNING: DB:|DB:) ') {
        $matched = $false
        foreach ($pattern in $allowed) {
            if ($line -match $pattern) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $unexpected += $line
        }
    }
}

if ($unexpected.Count -gt 0) {
    $unexpected | ForEach-Object { Write-Error "Unexpected Flyway/Postgres warning: $_" }
    throw "Flyway warning registry enforcement failed"
}

Write-Host "Flyway warning registry PASS"
