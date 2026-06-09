$base = 'C:\biodiscovery\01_foundation'
$runtimePath = Join-Path $base 'lib\foundation_runtime.sh'
$runtime = [System.IO.File]::ReadAllText($runtimePath)
if ($runtime -notmatch 'foundation_absolute_path\(\)') {
  $runtime = $runtime.TrimEnd() + @'

foundation_absolute_path() {
  local input_path="$1"
  [[ -n "${input_path}" ]] || fail "Path cannot be empty."

  local parent leaf
  parent="$(dirname "${input_path}")"
  leaf="$(basename "${input_path}")"

  if [[ "${input_path}" == /* ]]; then
    if [[ -d "${input_path}" ]]; then
      (cd "${input_path}" && pwd -P)
    elif [[ -d "${parent}" ]]; then
      printf '%s/%s\n' "$(cd "${parent}" && pwd -P)" "${leaf}"
    else
      fail "Cannot resolve absolute path because parent directory does not exist: ${parent}"
    fi
  else
    if [[ -d "${input_path}" ]]; then
      (cd "${input_path}" && pwd -P)
    elif [[ -d "${parent}" ]]; then
      printf '%s/%s\n' "$(cd "${parent}" && pwd -P)" "${leaf}"
    else
      fail "Cannot resolve relative path because parent directory does not exist: ${parent}"
    fi
  fi
}

foundation_absolute_dir() {
  foundation_absolute_path "$1"
}
'@ + "`n"
  [System.IO.File]::WriteAllText($runtimePath, $runtime, [System.Text.UTF8Encoding]::new($false))
  Write-Output "Updated lib\foundation_runtime.sh"
}

$scriptFiles = Get-ChildItem -LiteralPath $base -Filter 'b001_*.sh' |
  Where-Object { $_.Name -match '^b001_\d\d_' } |
  Sort-Object Name

foreach ($file in $scriptFiles) {
  $path = $file.FullName
  $text = [System.IO.File]::ReadAllText($path)
  $original = $text

  $text = $text.Replace('  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"', '  OUTPUT_ROOT="$(foundation_absolute_dir "${OUTPUT_ROOT}")"' + "`n" + '  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"')

  if ($file.Name -eq 'b001_01_runtime_safety_preflight.sh') {
    $text = $text.Replace('  if [[ -z "${OUTPUT_DIR}" ]]; then' + "`n" + '    OUTPUT_DIR="${PROJECT_NAME}/.foundation/preflight"' + "`n" + '  fi' + "`n" + '  REPORT_PATH="${OUTPUT_DIR}/execution_report.md"',
      '  if [[ -z "${OUTPUT_DIR}" ]]; then' + "`n" + '    OUTPUT_DIR="${PROJECT_NAME}/.foundation/preflight"' + "`n" + '  fi' + "`n" + '  OUTPUT_DIR="$(foundation_absolute_dir "${OUTPUT_DIR}")"' + "`n" + '  REPORT_PATH="${OUTPUT_DIR}/execution_report.md"')
  }

  if ($text -ne $original) {
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Output "Updated $($file.Name)"
  }
}

$templatePath = 'C:\Users\nabil\Documents\biomedical_discovery_ai\tools\templates\b001_domain_script.template.sh'
if (Test-Path -LiteralPath $templatePath) {
  $template = [System.IO.File]::ReadAllText($templatePath)
  $originalTemplate = $template
  $template = $template.Replace('  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"', '  OUTPUT_ROOT="$(foundation_absolute_dir "${OUTPUT_ROOT}")"' + "`n" + '  PROJECT_ROOT="${OUTPUT_ROOT%/}/${PROJECT_NAME}"')
  if ($template -ne $originalTemplate) {
    [System.IO.File]::WriteAllText($templatePath, $template, [System.Text.UTF8Encoding]::new($false))
    Write-Output "Updated workspace generator template"
  }
}
