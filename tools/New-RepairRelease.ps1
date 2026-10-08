param(
 [string]$ClientRoot='C:\RO-Server\RO-Client-Master',
 [ValidatePattern('^repair-v[0-9]+$')][string]$ReleaseTag='repair-v2',
 [string]$OutputPath=''
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=(Resolve-Path -LiteralPath $ClientRoot).Path.TrimEnd('\')
if(Get-Process -Name '2021-11-03_Ragexe_patched','RO-Launcher' -ErrorAction SilentlyContinue){throw 'Close the game and launcher first.'}
if(-not(Test-Path -LiteralPath (Join-Path $root 'DATA.INI'))){throw 'Select the Master Client directory.'}
if(-not $OutputPath){$OutputPath=Join-Path (Split-Path $root -Parent) ('publish-'+$ReleaseTag)}
$out=[IO.Path]::GetFullPath($OutputPath)
if($out -eq $root -or $out.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be outside Client.'}
if(Test-Path -LiteralPath $out){throw 'Output folder already exists. Use a new tag or move the previous output.'}
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

if($records.Count -eq 0){throw 'No game files found.'}
$limit=2147483648L
foreach($f in $records){if($f.size -ge $limit){throw ('Release asset must be smaller than 2 GiB: '+$f.path)}}
New-Item -ItemType Directory -Path $out|Out-Null
$zipPath=Join-Path $out 'client-small-files.zip'
$stream=$null;$zip=$null
try{
 $stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew)
 $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
 foreach($f in $records){
  if($f.path.ToLowerInvariant().EndsWith('.grf')){
   if($f.path.Contains('/')){throw 'Only root GRF assets are supported.'}
   continue
  }
  $source=Join-Path $root $f.path.Replace('/','\')
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$source,$f.path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null
  # Detect edits made during packaging.
  if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $f.sha256){throw ('File changed during packaging: '+$f.path)}
 }
 $zip.Dispose();$zip=$null;$stream.Dispose();$stream=$null
 if((Get-Item -LiteralPath $zipPath).Length -ge $limit){throw 'Small-files ZIP exceeds release asset size limit.'}
 $base='https://github.com/rayjhih8263/RO-Launcher/releases/download/'+$ReleaseTag+'/'
 $manifest=[ordered]@{
  schemaVersion=1
  purpose='repair-v1'
  archive=[ordered]@{url=$base+'client-small-files.zip';size=[long](Get-Item -LiteralPath $zipPath).Length;sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()}
  baseUrl=$base
  files=@($records)
 }
 $utf8=New-Object Text.UTF8Encoding($false)
 [IO.File]::WriteAllText((Join-Path $out 'manifest-v1.json'),($manifest|ConvertTo-Json -Depth 6),$utf8)
 $assets=@($zipPath)
 foreach($f in $records){
  if($f.path.ToLowerInvariant().EndsWith('.grf')){
   $source=Join-Path $root $f.path
   if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $f.sha256){throw ('GRF changed: '+$f.path)}
   $assets+=$source
  }
 }
 [IO.File]::WriteAllLines((Join-Path $out 'upload-files.txt'),[string[]]$assets,$utf8)
 Write-Host ('Prepared '+$records.Count+' files for release tag '+$ReleaseTag)
 Write-Host ('Output: '+$out)
 Write-Host 'Upload every path in upload-files.txt to a NEW release with that tag.'
 Write-Host 'Keep Master files unchanged until upload finishes.'
 Write-Host 'Do not publish manifest-v1.json until every release asset is uploaded and verified.'
 Write-Host 'This prepares repair assets only; game THOR updates are prepared separately.'
}catch{
 if($zip){$zip.Dispose();$zip=$null}
 if($stream){$stream.Dispose();$stream=$null}
 Remove-Item -LiteralPath $out -Recurse -Force
 throw
}finally{
 if($zip){$zip.Dispose()}
 if($stream){$stream.Dispose()}
}
