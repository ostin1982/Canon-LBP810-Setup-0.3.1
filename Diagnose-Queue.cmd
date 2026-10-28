@echo off
cd /d "%~dp0"
echo Collecting Canon LBP-810 diagnostics...
echo Canon LBP-810 full queue diagnostic > diagnostic-queue.txt
echo Package folder: %~dp0 >> diagnostic-queue.txt
if exist Lbp810Usb.exe Lbp810Usb.exe --status >> diagnostic-queue.txt 2>&1
powershell.exe -NoProfile -Command "$ErrorActionPreference='Continue'; '--- Windows queue ---'; Get-Printer -Name 'Canon LBP-810 (USB)' -ErrorAction Continue | Format-List Name,DriverName,PortName,PrinterStatus,Comment; '--- Pending jobs ---'; Get-PrintJob -PrinterName 'Canon LBP-810 (USB)' -ErrorAction Continue | Format-List ID,DocumentName,JobStatus; '--- Local port ---'; Get-PrinterPort -Name 'CanonLBP810_Local_18100' -ErrorAction Continue | Format-List Name,PrinterHostAddress,PortNumber,SNMPEnabled; '--- Bridge process ---'; Get-Process Lbp810Bridge -ErrorAction Continue | Format-List Id,Path,StartTime; '--- Listener ---'; Get-NetTCPConnection -LocalPort 18100 -ErrorAction Continue | Format-Table State,OwningProcess; '--- Data directory ---'; $data=Join-Path $env:LOCALAPPDATA 'Lbp810Bridge'; $data; '--- Bridge log ---'; Get-Content -LiteralPath (Join-Path $data 'bridge.log') -Tail 40 -ErrorAction Continue; '--- Latest job logs ---'; Get-ChildItem -LiteralPath (Join-Path $data 'jobs') -Directory -ErrorAction Continue | Sort-Object Name -Descending | Select-Object -First 5 | ForEach-Object { $_.Name; Get-Content -LiteralPath (Join-Path $_.FullName 'state.txt') -ErrorAction Continue; Get-Content -LiteralPath (Join-Path $_.FullName 'print.log') -Tail 30 -ErrorAction Continue }" >> diagnostic-queue.txt 2>&1
type diagnostic-queue.txt
echo.
echo Send diagnostic-queue.txt from this folder.
pause
