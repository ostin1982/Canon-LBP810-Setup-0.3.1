param([switch]$DryRun,[switch]$NoStartup,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$queue='Canon LBP-810 (USB)'
$port='CanonLBP810_Local_18100'
$owner='Canon LBP-810 USB bridge 0.3'
$root=$PSScriptRoot
foreach($file in 'Lbp810Usb.exe','Lbp810Bridge.exe','Raster.dll','Render-Job.ps1') {
    if(-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "Missing $file; extract the whole ZIP first." }
}
# .NET Framework refuses LoadFrom of a DLL carrying an Internet Zone.Identifier.
# Only remove the download mark from our exact, verified Raster.dll.
$raster=Join-Path $root 'Raster.dll'
$expectedRaster='6EBCA7519A778FAD52B2DDE5782EDB66A2A19D052577D8DCD1199C85620CE27E'
$sha=[Security.Cryptography.SHA256]::Create()
$inputFile=[IO.File]::OpenRead($raster)
try { $actualRaster=[BitConverter]::ToString($sha.ComputeHash($inputFile)).Replace('-','') }
finally { $inputFile.Dispose(); $sha.Dispose() }
if($actualRaster -ne $expectedRaster) { throw 'Raster.dll hash mismatch. Installation stopped.' }
Unblock-File -LiteralPath $raster
Add-Type -Path $raster
if(-not [Environment]::Is64BitOperatingSystem) { throw 'This package requires Windows x64.' }
$null=[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime]
if($CheckOnly) { 'PREFLIGHT OK: verified Raster.dll, removed its download block, loaded Windows PDF API. Queue and startup were not changed.'; exit 0 }
$running=Get-Process -Name Lbp810Bridge -ErrorAction SilentlyContinue
if($running) { throw 'Bridge is already running. Exit it using its tray icon before installing/updating. DLL download-block repair was already applied.' }
$driver=Get-PrinterDriver -Name 'Microsoft Print To PDF' -ErrorAction SilentlyContinue
if(-not $driver) { throw 'Microsoft Print To PDF is not installed. Enable Microsoft Print to PDF in Windows Features, then run installation again.' }
$existing=Get-Printer -Name $queue -ErrorAction SilentlyContinue
if($existing -and $existing.Comment -ne $owner) { throw 'An unrelated queue already has this name; it will not be changed.' }
$existingPort=Get-PrinterPort -Name $port -ErrorAction SilentlyContinue
if($existingPort) {
    if($existingPort.PrinterHostAddress -ne '127.0.0.1' -or $existingPort.PortNumber -ne 18100) { throw 'The reserved port name belongs to a different configuration.' }
} else { Add-PrinterPort -Name $port -PrinterHostAddress '127.0.0.1' -PortNumber 18100 }
if(-not $existing) { Add-Printer -Name $queue -DriverName $driver.Name -PortName $port -Comment $owner }
Set-PrintConfiguration -PrinterName $queue -PaperSize A4 -DuplexingMode OneSided
# Add-PrinterPort defaults to SNMP disabled when no SNMP options are supplied.
if((Get-PrinterPort -Name $port).SNMPEnabled) { throw 'Disable SNMP on this port in Printer properties / Ports / Configure port, then rerun installation.' }
$bridge=Join-Path $root 'Lbp810Bridge.exe'
$startArgs=@{FilePath=$bridge;WindowStyle='Hidden';WorkingDirectory=$root}
if($DryRun) { $startArgs.ArgumentList='--dry-run' }
Start-Process @startArgs
if(-not $NoStartup -and -not $DryRun) {
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Canon LBP-810 USB bridge.lnk'))
    $shortcut.TargetPath=$bridge; $shortcut.WorkingDirectory=$root; $shortcut.WindowStyle=7; $shortcut.Save()
}
"Installed queue: $queue"
"Bridge folder: $root"
"DryRun: $DryRun"
"Logs: $env:LOCALAPPDATA\Lbp810Bridge"
if(-not $DryRun) { 'Select Canon LBP-810 (USB) in the application print dialog. A4 / single-sided.' }
