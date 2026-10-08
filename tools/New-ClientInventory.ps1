param(
  [Parameter(Mandatory=$true)][string]$ClientRoot,
  [string]$OutputPath = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $ClientRoot).Path.TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $root '2021-11-03_Ragexe_patched.exe'))) {
  throw "The selected directory is not the expected RO Client."
}
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path $root -Parent) 'client-inventory.json' }
$folders = @('data','System','BGM','Navigationdata','AI','AI_sakray')
$rootNames = @('DATA.INI','RO-Launcher.yml')
$rootExtensions = @('.exe','.dll','.asi','.grf')
$records = @()
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName)
foreach ($file in $files) {
  if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked files are not supported." }
  $rel = $file.FullName.Substring($root.Length + 1).Replace('\','/')
  $parts = $rel.Split('/')
  $include = $false
  if ($parts.Length -eq 1) {
    $include = ($rootNames -contains $file.Name) -or ($rootExtensions -contains $file.Extension)
  } elseif ($folders -contains $parts[0]) {
    $include = $true
  }
  if ($rel -match '^(AI|AI_sakray)/USER_AI(/|$)') { $include = $false }
  if (-not $include) { continue }
  if ($rel -match '(?i)(^|/)(launcher-test\.txt|.*\.(bak|log|tmp))$') { continue }
  Write-Host ("Hashing: " + $rel)
  $records += [ordered]@{
    path = $rel
    size = [long]$file.Length
    sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}
$result = [ordered]@{
  schemaVersion = 1
  purpose = 'inventory-only; download URLs are not configured'
  files = @($records)
}
$json = $result | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host ("Complete: " + $OutputPath)
Write-Host ("Files: " + $records.Count)
