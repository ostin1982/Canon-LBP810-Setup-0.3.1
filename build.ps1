param([Parameter(Mandatory=$true)][string]$Compiler)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$sources = @(Get-ChildItem -LiteralPath "$root/vendor/libcapt/libcapt" -Recurse -Filter '*.cpp' | ForEach-Object FullName)
& $Compiler '-std=c++23' '-O2' '-Wall' '-Wextra' '-static' '-municode' '-I' "$root/vendor/libcapt" '-I' "$root/vendor/libcapt/libcapt" "$root/src/main.cpp" @sources '-lsetupapi' '-o' "$root/Lbp810Usb.exe"
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
& "$root/Lbp810Usb.exe" --self-test
if ($LASTEXITCODE -ne 0) { throw 'Offline tests failed' }
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:library /reference:System.Drawing.dll "/out:$root\Raster.dll" "$root\src\Raster.cs"
if ($LASTEXITCODE -ne 0) { throw 'Raster.dll compilation failed' }
& $csc /nologo /target:winexe /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Core.dll "/out:$root\Lbp810Bridge.exe" "$root\src\Bridge.cs"
if ($LASTEXITCODE -ne 0) { throw 'Bridge compilation failed' }
