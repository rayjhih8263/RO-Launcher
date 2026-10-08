param(
 [string]$ClientRoot='C:\RO-Server\RO-Client-Release',
 [string]$OutputPath='C:\RO-Server\RO-Update-0003'
)
$ErrorActionPreference='Stop'
$source=Join-Path $ClientRoot 'data\pettalktable.xml'
$expected='1c3189938817ba04229fa067a3f0e15947da22bf307e53a085c23bba7d2d7a98'
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $expected){throw 'Client XML differs from the uploaded baseline. Stop and check it first.'}
if(Test-Path -LiteralPath $OutputPath){throw 'Output already exists; choose a new empty path.'}
$out=[IO.Path]::GetFullPath($OutputPath)
$root=(Resolve-Path -LiteralPath $ClientRoot).Path.TrimEnd('\')
if($out -eq $root -or $out.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be outside the game Client.'}
$dir=Join-Path $out 'patch-data\data'
New-Item -ItemType Directory -Path $dir -Force|Out-Null
# Append an ASCII XML comment without decoding or changing EUC-KR bytes.
$original=[IO.File]::ReadAllBytes($source)
$marker=[Text.Encoding]::ASCII.GetBytes("`r`n<!-- RO synchronized update test 003 -->`r`n")
$target=Join-Path $dir 'pettalktable.xml'
$stream=[IO.File]::Create($target)
try{$stream.Write($original,0,$original.Length);$stream.Write($marker,0,$marker.Length)}finally{$stream.Dispose()}
$config="use_grf_merging: false`r`ninclude_checksums: true`r`nentries:`r`n  - relative_path: data/pettalktable.xml`r`n"
[IO.File]::WriteAllText((Join-Path $out 'test-patch.yml'),$config,(New-Object Text.UTF8Encoding($false)))
Write-Host ('Prepared: '+$out)
Write-Host ('XML SHA256: '+(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)
Write-Host 'Original Client unchanged. No files uploaded or published.'
Write-Host 'Copy mkpatch.exe into this folder, then run:'
Write-Host 'mkpatch.exe test-patch.yml -p patch-data -o 0003-repair-test.thor'
