param(
    [string]$Root = "$PSScriptRoot\.."
)

$ErrorActionPreference = "Stop"

$rootFull = [System.IO.Path]::GetFullPath($Root)
$patterns = @(
    'AKIA[0-9A-Z]{16}',
    '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'ghp_[A-Za-z0-9_]{36,}',
    'github_pat_[A-Za-z0-9_]{20,}',
    'sk-[A-Za-z0-9]{20,}',
    '(?i)(password|secret|api[_-]?key)\s*=\s*["''][^"'']{12,}["'']'
)

$allow = @(
    'bdai_dev_password',
    'bdai_dev_jwt_secret_not_for_production',
    'unit-test-secret',
    'GOVERNANCE_JWT_HS256_SECRET',
    'GOVERNANCE_OIDC_JWKS_URI'
)

$files = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
    Where-Object {
        $_.FullName -notmatch '\\.git\\' -and
        $_.FullName -notmatch '__pycache__' -and
        $_.FullName -notmatch '\\validation\\last_flyway_validation\.log$'
    }

$findings = @()
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
        if ($text -match $pattern) {
            $allowed = $false
            foreach ($token in $allow) {
                if ($text.Contains($token)) {
                    $allowed = $true
                    break
                }
            }
            if (-not $allowed) {
                $findings += "$($file.FullName): pattern $pattern"
            }
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | ForEach-Object { Write-Error $_ }
    throw "Secret scan failed"
}

Write-Host "Secret scan PASS"
