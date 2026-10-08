param([string]$ClientRoot=".",[string]$InventoryPath="..\client-inventory.json")
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=(Resolve-Path -LiteralPath $ClientRoot).Path.TrimEnd('\')
$inventory=Get-Content -LiteralPath $InventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$out=Join-Path (Split-Path $root -Parent) 'client-small-files.zip'
if(Test-Path -LiteralPath $out){throw "Output already exists. Move it elsewhere before running again."}
$stream=[IO.File]::Open($out,[IO.FileMode]::CreateNew)
$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try{
 foreach($f in $inventory.files){
  $rel=[string]$f.path
  if($rel.ToLowerInvariant().EndsWith('.grf')){continue}
  if($rel -match '(^/|^[A-Za-z]:|(^|/)\.\.(/|$)|\\)'){throw "Invalid path: $rel"}
  $source=Join-Path $root $rel.Replace('/','\')
  if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing file: $rel"}
  $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  if($hash -ne $f.sha256 -or (Get-Item -LiteralPath $source).Length -ne $f.size){throw "File changed since inventory: $rel"}
  Write-Host ("Packing: "+$rel)
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$source,$rel,[IO.Compression.CompressionLevel]::Optimal)|Out-Null
 }
}catch{
 $zip.Dispose();$stream.Dispose()
 Remove-Item -LiteralPath $out -Force
 throw
}finally{$zip.Dispose();$stream.Dispose()}
Write-Host ("Complete: "+$out)
Write-Host ("SHA256: "+(Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash)
