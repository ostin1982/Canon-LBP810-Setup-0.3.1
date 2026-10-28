@echo off
cd /d "%~dp0"
echo LBP-810 USB diagnostic - no test page is printed.
Lbp810Usb.exe --self-test > diagnostic.txt 2>&1
Lbp810Usb.exe --list >> diagnostic.txt 2>&1
Lbp810Usb.exe --status >> diagnostic.txt 2>&1
type diagnostic.txt
echo.
echo Results saved to diagnostic.txt in this folder.
pause
