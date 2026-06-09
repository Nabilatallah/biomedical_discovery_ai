$RootPath = "C:\biodiscovery\BDAI_Done"

$guard = @'
sign_integrity_artifacts() {
  if [[ "${FOUNDATION_ENABLE_SIGNING:-no}" != "yes" ]]; then
    cat > "${SIGNING_STATUS}" <<'EOF'
# Signing Status

Signing skipped because FOUNDATION_ENABLE_SIGNING is not yes.
EOF
    return 0
  fi
'@

$preflightGuard = @'
step_12_sign_integrity_artifacts() {
  if [[ "${FOUNDATION_ENABLE_SIGNING:-no}" != "yes" ]]; then
    local signing_log="${PROJECT_ROOT}/.foundation/signing_status.md"
    cat > "${signing_log}" <<'EOF'
# Signing Status

Signing skipped because FOUNDATION_ENABLE_SIGNING is not yes.
EOF
    return 0
  fi
'@

$changed = 0
Get-ChildItem -LiteralPath $RootPath -Recurse -File -Include "*.sh" | ForEach-Object {
  $path = $_.FullName
  $text = [System.IO.File]::ReadAllText($path)
  if ($text -notmatch 'sign_integrity_artifacts\(\)' -and $text -notmatch 'step_12_sign_integrity_artifacts\(\)') {
    return
  }
  if ($text -match 'FOUNDATION_ENABLE_SIGNING') {
    return
  }

  $original = $text
  $text = [regex]::Replace($text, '(?m)^sign_integrity_artifacts\(\) \{\r?\n', $guard + "`n")
  $text = [regex]::Replace($text, '(?m)^step_12_sign_integrity_artifacts\(\) \{\r?\n', $preflightGuard + "`n")

  if ($text -ne $original) {
    $text = $text.Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    $changed += 1
  }
}

Write-Output "Patched signing guards in $changed files"
