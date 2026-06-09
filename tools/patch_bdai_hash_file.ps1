$Path = "C:\biodiscovery\BDAI_Done\tasks\B001_foundation\lib\foundation_integrity.sh"
$text = [System.IO.File]::ReadAllText($Path)

$old = @'
hash_file() {
  local file_path="$1"
  if [[ ! -f "${file_path}" ]]; then
    printf 'FILE_NOT_FOUND'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file_path}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file_path}" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "${file_path}" | awk '{print $2}'
  else
    printf 'HASH_COMMAND_UNAVAILABLE'
  fi
}
'@

$new = @'
hash_file() {
  local file_path="$1"
  local digest_output digest
  if [[ ! -f "${file_path}" ]]; then
    printf 'FILE_NOT_FOUND'
  elif command -v sha256sum >/dev/null 2>&1; then
    digest_output="$(sha256sum "${file_path}")"
    digest="${digest_output%%[[:space:]]*}"
    printf '%s' "${digest}"
  elif command -v shasum >/dev/null 2>&1; then
    digest_output="$(shasum -a 256 "${file_path}")"
    digest="${digest_output%%[[:space:]]*}"
    printf '%s' "${digest}"
  elif command -v openssl >/dev/null 2>&1; then
    digest_output="$(openssl dgst -sha256 "${file_path}")"
    digest="${digest_output##* }"
    printf '%s' "${digest}"
  else
    printf 'HASH_COMMAND_UNAVAILABLE'
  fi
}
'@

if (-not $text.Contains($old)) {
  throw "Expected hash_file block was not found"
}

$text = $text.Replace($old, $new).Replace("`r`n", "`n")
[System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
Write-Output "Patched hash_file in $Path"
