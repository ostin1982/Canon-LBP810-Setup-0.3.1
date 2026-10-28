$ErrorActionPreference='Stop'
$queue='Canon LBP-810 (USB)'
$printer=Get-Printer -Name $queue -ErrorAction SilentlyContinue
if($printer) {
    if($printer.Comment -ne 'Canon LBP-810 USB bridge 0.3') { throw 'Queue ownership mismatch; no changes made.' }
    if(Get-PrintJob -PrinterName $queue) { throw 'Queue contains jobs. Cancel or finish them first.' }
    Remove-Printer -Name $queue
}
$port=Get-PrinterPort -Name 'CanonLBP810_Local_18100' -ErrorAction SilentlyContinue
if($port -and $port.PrinterHostAddress -eq '127.0.0.1' -and $port.PortNumber -eq 18100) {
    Remove-PrinterPort -Name $port.Name
}
$link=Join-Path ([Environment]::GetFolderPath('Startup')) 'Canon LBP-810 USB bridge.lnk'
if(Test-Path -LiteralPath $link) {
    $shell=New-Object -ComObject WScript.Shell
    if($shell.CreateShortcut($link).TargetPath -eq (Join-Path $PSScriptRoot 'Lbp810Bridge.exe')) { Remove-Item -LiteralPath $link }
}
'Queue and owned startup link removed. Exit the bridge using its tray icon. Job logs are retained.'
