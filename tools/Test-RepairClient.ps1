param([string]$ClientRoot=".",[switch]$Repair)
$ErrorActionPreference="Stop"
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=(Resolve-Path -LiteralPath $ClientRoot).Path.TrimEnd('\')
if(Get-Process -Name '2021-11-03_Ragexe_patched','RO-Launcher' -ErrorAction SilentlyContinue){throw "Close the game and launcher before checking or repairing."}
if(-not(Test-Path -LiteralPath (Join-Path $root 'DATA.INI'))){throw "Select the RO Client directory."}
function SafePath([string]$rel){
 if(-not $rel -or $rel -match '(^/|[:\\]|(^|/)\.\.(/|$))'){throw "Unsafe path: $rel"}
 $p=[IO.Path]::GetFullPath((Join-Path $root $rel.Replace('/','\')))
 if(-not $p.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Path outside Client"}
 $cursor=$p
 while($cursor -and $cursor.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){
  if(Test-Path -LiteralPath $cursor){
   if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Linked paths are not supported: $cursor"}
  }
  if($cursor -eq $root){break}
  $cursor=Split-Path $cursor -Parent
 }
 return $p
}
function ValidFile([string]$path,$f){
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $false}
 if((Get-Item -LiteralPath $path).Length -ne [long]$f.size){return $false}
 return ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $f.sha256)
}
$manifestUrl='https://raw.githubusercontent.com/rayjhih8263/RO-Launcher/main/repair/manifest-v1.json'
$m=Invoke-RestMethod -Uri ($manifestUrl+'?t='+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
if($m.schemaVersion -ne 1 -or $m.purpose -ne 'repair-v1'){throw "Unsupported manifest"}
$bad=@();$seen=@{};$i=0
foreach($f in $m.files){
 $p=SafePath $f.path
 if($seen.ContainsKey($p)){throw "Duplicate manifest path"}
 $seen[$p]=$true
 if($f.sha256 -notmatch '^[a-f0-9]{64}$' -or [long]$f.size -lt 0){throw "Invalid manifest hash or size"}
 $i++;Write-Progress -Activity 'Checking Client' -Status $f.path -PercentComplete (100*$i/$m.files.Count)
 if(-not(ValidFile $p $f)){Write-Host ('MISSING OR CHANGED: '+$f.path);$bad+=,$f}
}
Write-Progress -Activity 'Checking Client' -Completed
Write-Host ('Checked: '+$m.files.Count+'; missing or changed: '+$bad.Count)
if(-not $Repair){Write-Host 'Check-only: no game files changed.';exit 0}
if($bad.Count -eq 0){Write-Host 'All files match.';exit 0}
$stage=Join-Path $root ('.ro-repair-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage|Out-Null
$wc=New-Object Net.WebClient
$archive=$null
try{
 $small=@($bad|Where-Object {-not $_.path.ToLowerInvariant().EndsWith('.grf')})
 if($small.Count -gt 0){
  $url=[Uri]$m.archive.url
  if($url.Scheme -ne 'https' -or $url.Host -ne 'github.com' -or -not $url.AbsolutePath.StartsWith('/rayjhih8263/RO-Launcher/releases/download/repair-v1/')){throw "Invalid archive URL"}
  $zipPath=Join-Path $stage 'small.zip'
  Write-Host 'Downloading small-file repair archive...'
  $wc.DownloadFile($url.AbsoluteUri,$zipPath)
  if(-not(ValidFile $zipPath $m.archive)){throw "Repair archive checksum failed"}
  $archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
 }
 # Verify every replacement before touching any existing game file.
 $ready=@();$n=0
 foreach($f in $bad){
  $n++;$temp=Join-Path $stage ($n.ToString()+'.ready')
  if($f.path.ToLowerInvariant().EndsWith('.grf')){
   if($f.path.Contains('/')){throw "Unexpected GRF path"}
   Write-Host ('Downloading: '+$f.path)
   $wc.DownloadFile($m.baseUrl+[Uri]::EscapeDataString($f.path),$temp)
  }else{
   $matches=@($archive.Entries|Where-Object {$_.FullName -ceq $f.path})
   if($matches.Count -ne 1){throw "Missing or duplicate ZIP entry"}
   if($matches[0].Length -ne [long]$f.size){throw "ZIP entry size mismatch"}
   [IO.Compression.ZipFileExtensions]::ExtractToFile($matches[0],$temp,$false)
  }
  if(-not(ValidFile $temp $f)){throw ('Replacement checksum failed: '+$f.path)}
  $ready+=,[pscustomobject]@{file=$f;temp=$temp}
 }
 if($archive){$archive.Dispose();$archive=$null}
 if(Get-Process -Name '2021-11-03_Ragexe_patched','RO-Launcher' -ErrorAction SilentlyContinue){throw "Game or launcher was opened. Close it and retry."}
 $backup=Join-Path $root ('.ro-repair-backup-'+[Guid]::NewGuid().ToString('N'))
 foreach($item in $ready){
  $target=SafePath $item.file.path
  $parent=Split-Path $target -Parent
  if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  if(Test-Path -LiteralPath $target){
   $save=Join-Path $backup $item.file.path.Replace('/','\')
   New-Item -ItemType Directory -Path (Split-Path $save -Parent) -Force|Out-Null
   # Supply a real backup path: Windows PowerShell can bind $null as an empty string.
   # Replace preserves the original at $save while installing the verified file.
   [IO.File]::Replace([string]$item.temp,[string]$target,[string]$save)
  }else{[IO.File]::Move($item.temp,$target)}
  Write-Host ('Repaired: '+$item.file.path)
 }
 Write-Host ('Repair complete. Original changed files retained at: '+$backup)
}finally{
 if($archive){$archive.Dispose()}
 $wc.Dispose()
 if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
}
