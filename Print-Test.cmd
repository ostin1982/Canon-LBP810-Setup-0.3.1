@echo off
cd /d "%~dp0"
echo This sends ONE A4 test page directly to a confirmed Canon LBP-810.
echo Load A4 paper and turn on the printer. Press Ctrl+C to cancel.
pause
Lbp810Usb.exe --print-test > print-test.txt 2>&1
type print-test.txt
echo.
echo Results saved to print-test.txt in this folder.
pause
