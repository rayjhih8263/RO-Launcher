param(
 [string]$ClientRoot='C:\RO-Server\RO-Client-Release',
 [Parameter(Mandatory=$true)][ValidateRange(4,9999)][int]$UpdateNumber,
 [string]$MkpatchPath='',
 [string]$OutputPath=''
)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$root=(Resolve-Path -LiteralPath $ClientRoot).Path.TrimEnd('\')
if(Get-Process -Name '2021-11-03_Ragexe_patched','RO-Launcher' -ErrorAction SilentlyContinue){throw 'Close game and launcher first.'}
if(-not(Test-Path -LiteralPath (Join-Path $root 'DATA.INI'))){throw 'Select the game Client directory.'}
$baseline=Invoke-RestMethod -Uri ('https://raw.githubusercontent.com/rayjhih8263/RO-Launcher/main/repair/manifest-v1.json?t='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
if($baseline.schemaVersion -ne 1 -or $baseline.purpose -ne 'repair-v1'){throw 'Unsupported baseline manifest.'}
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
  if ($rel -in @('RO-Launcher.exe','RO-Launcher.yml')) { $include = $false }
  if (-not $include) { continue }
  if ($rel -match '(?i)(^|/)(launcher-test\.txt|.*\.(bak|log|tmp))$') { continue }
  Write-Host ("Hashing: " + $rel)
  $records += [ordered]@{
    path = $rel
    size = [long]$file.Length
    sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

$previous=@{};$current=@{};$changed=@()
foreach($f in $baseline.files){if($previous.ContainsKey($f.path)){throw 'Duplicate baseline path'};$previous[$f.path]=$f}
foreach($f in $records){
 $current[$f.path]=$f
 $old=$previous[$f.path]
 if(-not $old -or [long]$old.size -ne [long]$f.size -or $old.sha256 -ne $f.sha256){$changed+=,$f}
}
$removed=@($previous.Keys|Where-Object {-not $current.ContainsKey($_)})
if($removed.Count){$removed|ForEach-Object {Write-Host ('REMOVED: '+$_)};throw 'File removal is not supported by this tool. Restore accidentally missing files before proceeding.'}
if(-not $changed.Count){Write-Host 'NO CHANGES. No package or upload needed.';exit 0}
foreach($f in $changed){Write-Host ('CHANGED: '+$f.path);if($f.size -ge 2147483648){throw 'Changed release asset exceeds 2 GiB.'}}
$plistText=(Invoke-WebRequest -UseBasicParsing -Uri ('https://raw.githubusercontent.com/rayjhih8263/RO-Launcher/main/docs/plist.txt?t='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds())).Content
$maximum=0
foreach($line in ($plistText -split "\r?\n")){
 if($line.Trim()){
  if($line -notmatch '^\s*([0-9]+)\s+\S+\s*$'){throw 'Invalid published patch list.'}
  $maximum=[Math]::Max($maximum,[int]$Matches[1])
 }
}
if($UpdateNumber -ne ($maximum+1)){throw ('Next update number must be '+($maximum+1))}
if(-not $MkpatchPath){$MkpatchPath=Join-Path $PSScriptRoot 'mkpatch.exe'}
$mkpatch=(Resolve-Path -LiteralPath $MkpatchPath).Path
$prefix=$UpdateNumber.ToString('0000')
if(-not $OutputPath){$OutputPath=Join-Path (Split-Path $root -Parent) ('RO-Update-'+$prefix)}
$out=[IO.Path]::GetFullPath($OutputPath)
if($out -eq $root -or $out.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be outside Client.'}
if(Test-Path -LiteralPath $out){throw 'Output already exists.'}
New-Item -ItemType Directory -Path $out|Out-Null
try{
 $stage=Join-Path $out 'patch-data';$assets=Join-Path $out 'upload'
 New-Item -ItemType Directory -Path $stage,$assets|Out-Null
 $utf8=New-Object Text.UTF8Encoding($false)
 $yaml=@('use_grf_merging: false','include_checksums: true','entries:')
 $urls=@{};$index=0
 foreach($f in $changed){
  $index++
  $source=Join-Path $root $f.path.Replace('/','\')
  $dest=Join-Path $stage $f.path.Replace('/','\')
  New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force|Out-Null
  Copy-Item -LiteralPath $source -Destination $dest
  if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $f.sha256){throw 'Source changed during copy.'}
  $ext=[IO.Path]::GetExtension($f.path)
  if($ext -notmatch '^\.[A-Za-z0-9]+$'){$ext='.bin'}
  $assetName=$prefix+'-repair-'+$index.ToString('0000')+$ext
  Copy-Item -LiteralPath $dest -Destination (Join-Path $assets $assetName)
  $urls[$f.path]='https://github.com/rayjhih8263/RO-Launcher/releases/download/patches/'+$assetName
  $yaml+=("  - relative_path: '"+$f.path.Replace("'","''")+"'")
 }
 $definition=Join-Path $out 'patch.yml'
 [IO.File]::WriteAllText($definition,($yaml -join [Environment]::NewLine)+[Environment]::NewLine,$utf8)
 $patchName=$prefix+'-update.thor';$patchPath=Join-Path $assets $patchName
 & $mkpatch $definition -p $stage -o $patchPath
 if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $patchPath)){throw 'mkpatch failed.'}
 if((Get-Item -LiteralPath $patchPath).Length -ge 2147483648){throw 'THOR asset exceeds 2 GiB.'}
 $newFiles=@()
 foreach($f in $records){
  if($urls.ContainsKey($f.path)){
   $newFiles+=,[pscustomobject]@{path=$f.path;size=$f.size;sha256=$f.sha256;url=$urls[$f.path]}
  }else{$newFiles+=,$previous[$f.path]}
 }
 $baseline.files=$newFiles
 [IO.File]::WriteAllText((Join-Path $out 'manifest-v1.json'),($baseline|ConvertTo-Json -Depth 8),$utf8)
 [IO.File]::WriteAllText((Join-Path $out 'plist.txt'),$plistText.TrimEnd()+[Environment]::NewLine+$UpdateNumber+' '+$patchName+[Environment]::NewLine,$utf8)
 $checks=@(Get-ChildItem -LiteralPath $assets -File|ForEach-Object {
  [ordered]@{name=$_.Name;size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
 })
 [IO.File]::WriteAllText((Join-Path $out 'upload-checksums.json'),($checks|ConvertTo-Json -Depth 5),$utf8)
 Write-Host ('Prepared '+$changed.Count+' changed files: '+$out)
 Write-Host 'Upload only the contents of the upload folder to the existing patches release.'
 Write-Host 'Keep unchanged release assets. Do not upload patch-data.'
 Write-Host 'Publish manifest-v1.json and plist.txt only after all uploaded assets are verified.'
 Write-Host 'No game files changed. Nothing uploaded or published automatically.'
}catch{
 Write-Host ('Preparation failed. Do not publish output: '+$out)
 throw
}
