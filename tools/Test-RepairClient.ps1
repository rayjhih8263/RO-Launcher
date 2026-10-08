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

# ASCII source keeps Chinese labels readable in Windows PowerShell 5.1.
function U([string]$text){return [regex]::Unescape($text)}
function DownloadWithProgress([string]$url,[string]$path,[long]$expected,[string]$label){
 $response=$null;$inputStream=$null;$outputStream=$null
 $clock=[Diagnostics.Stopwatch]::StartNew();$last=([long]-1000);$received=[long]0
 $activity=(U '\u4e0b\u8f09\u4fee\u5fa9\u6a94\u6848')
 try{
  Write-Progress -Id 2 -Activity $activity -Status ((U '\u9023\u7dda\u4e2d\uff1a')+$label) -PercentComplete 0
  $request=[Net.HttpWebRequest]::Create($url)
  $request.Timeout=30000;$request.ReadWriteTimeout=30000
  $response=$request.GetResponse()
  $inputStream=$response.GetResponseStream()
  $outputStream=[IO.File]::Create($path)
  $buffer=New-Object byte[] 65536
  while(($read=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
   $outputStream.Write($buffer,0,$read);$received+=$read
   if($received -gt $expected){throw "Download exceeds expected size"}
   if($clock.ElapsedMilliseconds-$last -ge 200){
    $percent=0
    if($expected -gt 0){$percent=[Math]::Min(100,[int](100.0*$received/$expected))}
    $speed=($received/1048576)/[Math]::Max(0.001,$clock.Elapsed.TotalSeconds)
    $status=('{0} | {1}% | {2:N1} / {3:N1} MB | {4:N1} MB/s' -f $label,$percent,($received/1048576),($expected/1048576),$speed)
    Write-Progress -Id 2 -Activity $activity -Status $status -PercentComplete $percent
    $last=$clock.ElapsedMilliseconds
   }
  }
  if($received -ne $expected){throw "Download size mismatch"}
 }finally{
  if($outputStream){$outputStream.Dispose()}
  if($inputStream){$inputStream.Dispose()}
  if($response){$response.Close()}
  Write-Progress -Id 2 -Activity $activity -Completed
 }
 Write-Host ((U '\u4e0b\u8f09\u5b8c\u6210\uff0c\u6b63\u5728\u9a57\u8b49\u6a94\u6848\uff1a')+$label)
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
 $i++;Write-Progress -Activity (U '\u6aa2\u67e5\u904a\u6232\u6a94\u6848') -Status $f.path -PercentComplete (100*$i/$m.files.Count)
 if(-not(ValidFile $p $f)){Write-Host ((U '\u7f3a\u5c11\u6216\u5df2\u8b8a\u66f4\uff1a')+$f.path);$bad+=,$f}
}
Write-Progress -Activity (U '\u6aa2\u67e5\u904a\u6232\u6a94\u6848') -Completed
Write-Host ((U '\u5df2\u6aa2\u67e5\uff1a')+$m.files.Count+(U '\uff1b\u9700\u4fee\u5fa9\uff1a')+$bad.Count)
if(-not $Repair){Write-Host (U '\u50c5\u6aa2\u67e5\uff0c\u672a\u8b8a\u66f4\u904a\u6232\u6a94\u6848\u3002');exit 0}
if($bad.Count -eq 0){Write-Host (U '\u6240\u6709\u6a94\u6848\u6b63\u5e38\u3002');exit 0}
$stage=Join-Path $root ('.ro-repair-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage|Out-Null
$archive=$null
try{
 $base=[Uri]$m.baseUrl
 if($base.Scheme -ne 'https' -or $base.Host -ne 'github.com' -or $base.AbsolutePath -notmatch '^/rayjhih8263/RO-Launcher/releases/download/repair-v[0-9]+/$'){throw 'Invalid repair base URL'}
 if($m.archive.url -ne ($m.baseUrl+'client-small-files.zip')){throw 'Archive and GRF release tags do not match'}
 $small=@($bad|Where-Object {-not $_.url -and -not $_.path.ToLowerInvariant().EndsWith('.grf')})
 if($small.Count -gt 0){
  $url=[Uri]$m.archive.url
  if($url.Scheme -ne 'https' -or $url.Host -ne 'github.com' -or $url.AbsolutePath -notmatch '^/rayjhih8263/RO-Launcher/releases/download/repair-v[0-9]+/client-small-files\.zip$'){throw "Invalid archive URL"}
  $zipPath=Join-Path $stage 'small.zip'
  Write-Host (U '\u6b63\u5728\u4e0b\u8f09\u5c0f\u6a94\u6848\u4fee\u5fa9\u5305\uff0c\u8acb\u7a0d\u5019\u2026')
  DownloadWithProgress $url.AbsoluteUri $zipPath ([long]$m.archive.size) 'client-small-files.zip'
  if(-not(ValidFile $zipPath $m.archive)){throw "Repair archive checksum failed"}
  $archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
 }
 # Verify every replacement before touching any existing game file.
 $ready=@();$n=0
 foreach($f in $bad){
  $n++;$temp=Join-Path $stage ($n.ToString()+'.ready')
  if($f.url){
   $fileUrl=[Uri]$f.url
   if($fileUrl.Scheme -ne 'https' -or $fileUrl.Host -ne 'github.com' -or $fileUrl.Query -or $fileUrl.Fragment -or $fileUrl.AbsolutePath -notmatch '^/rayjhih8263/RO-Launcher/releases/download/(patches|repair-v[0-9]+)/[A-Za-z0-9._-]+$'){throw 'Invalid individual repair URL'}
   DownloadWithProgress $fileUrl.AbsoluteUri $temp ([long]$f.size) $f.path
  }elseif($f.path.ToLowerInvariant().EndsWith('.grf')){
   if($f.path.Contains('/')){throw "Unexpected GRF path"}
   Write-Host ((U '\u6b63\u5728\u4e0b\u8f09\uff1a')+$f.path)
   DownloadWithProgress ($m.baseUrl+[Uri]::EscapeDataString($f.path)) $temp ([long]$f.size) $f.path
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
  Write-Host ((U '\u5df2\u4fee\u5fa9\uff1a')+$item.file.path)
 }
 Write-Host (U '\u4fee\u5fa9\u5b8c\u6210\u3002')
 if(Test-Path -LiteralPath $backup){Write-Host ((U '\u539f\u6a94\u6848\u5099\u4efd\u65bc\uff1a')+$backup)}
}finally{
 if($archive){$archive.Dispose()}
 if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
}
