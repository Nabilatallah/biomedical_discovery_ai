$Path = "C:\biodiscovery\BDAI_Done\tasks\B001_foundation\b001_35_developer_tooling.sh"
$text = [System.IO.File]::ReadAllText($Path)
$text = $text.Replace('COMPONENT_ROOT="."', 'COMPONENT_ROOT="tools/developer-tooling"')
$text = $text.Replace("`r`n", "`n")
[System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
Write-Output "Scoped b001_35 component root to tools/developer-tooling"
