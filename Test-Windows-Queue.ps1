# Prints two pages through the Windows queue. Use ONLY while bridge --dry-run
# is active for an offline integration test. Normal bridge mode prints on paper.
param([switch]$ConfirmPhysicalPrint)
$ErrorActionPreference='Stop'
if(-not $ConfirmPhysicalPrint) {
    $log=Join-Path $env:LOCALAPPDATA 'Lbp810Bridge/bridge.log'
    if(-not (Test-Path -LiteralPath $log)) { throw 'Bridge log not found' }
    $lastStart=Get-Content -LiteralPath $log | Where-Object { $_ -like '*Bridge 0.3 started*' } | Select-Object -Last 1
    if($lastStart -notlike '*DryRun=True') { throw 'Use bridge --dry-run for this test, or explicitly pass -ConfirmPhysicalPrint to print two sheets.' }
}
Add-Type -AssemblyName System.Drawing
$doc=New-Object System.Drawing.Printing.PrintDocument
$doc.PrinterSettings.PrinterName='Canon LBP-810 (USB)'
$doc.DocumentName='Canon LBP-810 bridge integration test (2 pages)'
$doc.PrintController=New-Object System.Drawing.Printing.StandardPrintController
$script:page=0
$doc.add_PrintPage({
    param($sender,$e)
    $script:page++
    $font=New-Object System.Drawing.Font('Arial',18)
    try {
        $e.Graphics.DrawString("Canon LBP-810 - Windows queue test",$font,[Drawing.Brushes]::Black,70,80)
        $cyrillic=-join ([char[]]@(0x041f,0x0440,0x043e,0x0432,0x0435,0x0440,0x043a,0x0430,0x0020,0x043f,0x0435,0x0447,0x0430,0x0442,0x0438))
        $e.Graphics.DrawString("Page $script:page of 2 / A4 / $cyrillic",$font,[Drawing.Brushes]::Black,70,140)
        $e.Graphics.DrawRectangle([Drawing.Pens]::Black,70,210,650,450)
        for($x=90;$x -lt 700;$x+=30) { $e.Graphics.DrawLine([Drawing.Pens]::Black,$x,230,$x,640) }
        $e.HasMorePages=$script:page -lt 2
    } finally { $font.Dispose() }
})
try { $doc.Print() } finally { $doc.Dispose() }
'Submitted 2-page job to the Windows queue.'
