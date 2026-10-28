@echo off
cd /d "%~dp0"
echo Canon LBP-810 - repair downloaded Raster.dll
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $dll=Join-Path (Get-Location).Path 'Raster.dll'; if(-not (Test-Path -LiteralPath $dll)) { throw 'Put this CMD in the program folder next to Raster.dll and Lbp810Bridge.exe.' }; $expected='6EBCA7519A778FAD52B2DDE5782EDB66A2A19D052577D8DCD1199C85620CE27E'; $sha=[Security.Cryptography.SHA256]::Create(); $input=[IO.File]::OpenRead($dll); try { $actual=[BitConverter]::ToString($sha.ComputeHash($input)).Replace('-','') } finally { $input.Dispose(); $sha.Dispose() }; if($actual -ne $expected) { throw 'Raster.dll differs from the original version 0.3. No changes made. Send this message for investigation.' }; Unblock-File -LiteralPath $dll; Add-Type -Path $dll; Write-Host 'REPAIR OK: Raster.dll loaded. Send ONE NEW page from Word to Canon LBP-810 (USB). Old failed jobs are not replayed.' } catch { Write-Host ('REPAIR FAILED: '+$_.Exception.Message); exit 1 }" > repair-result.txt 2>&1
set "repairExit=%errorlevel%"
type repair-result.txt
echo.
echo Result saved to repair-result.txt in this folder.
pause
exit /b %repairExit%

