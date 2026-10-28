@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" > "%~dp0install-result.txt" 2>&1
set "installExit=%errorlevel%"
type "%~dp0install-result.txt"
echo.
if "%installExit%"=="0" echo INSTALLATION OK. Select Canon LBP-810 (USB) in your application.
if not "%installExit%"=="0" echo INSTALLATION FAILED. See install-result.txt in this folder.
echo If Windows denied access, run this CMD as administrator.
pause
exit /b %installExit%
