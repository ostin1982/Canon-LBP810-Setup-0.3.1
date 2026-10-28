param([Parameter(Mandatory=$true)][string]$Pdf,[Parameter(Mandatory=$true)][string]$JobDir,[switch]$DryRun)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
Add-Type -Path "$PSScriptRoot/Raster.dll"
$null=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null=[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime]
$null=[Windows.Storage.Streams.InMemoryRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
$null=[Windows.Data.Pdf.PdfPageRenderOptions,Windows.Data.Pdf,ContentType=WindowsRuntime]
$generic=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1)
$actionMethod=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1)
function Await-Value($Operation,[Type]$Type) {
    $task=$generic.MakeGenericMethod($Type).Invoke($null,@($Operation))
    if(-not $task.Wait(120000)) { throw 'PDF operation timeout' }
    $task.GetAwaiter().GetResult()
}
$file=Await-Value ([Windows.Storage.StorageFile]::GetFileFromPathAsync([IO.Path]::GetFullPath($Pdf))) ([Windows.Storage.StorageFile])
$document=Await-Value ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
if($document.PageCount -lt 1 -or $document.PageCount -gt 500) { throw 'Expected 1..500 pages' }
"PDF pages: $($document.PageCount)"
for($i=0;$i -lt $document.PageCount;$i++) {
    $page=$document.GetPage($i)
    $stream=New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $png=Join-Path $JobDir ('page-{0:D4}.png' -f ($i+1))
    $pbm=Join-Path $JobDir ('page-{0:D4}.pbm' -f ($i+1))
    try {
        $options=New-Object Windows.Data.Pdf.PdfPageRenderOptions
        $scale=[Math]::Min(4960.0/$page.Size.Width,7014.0/$page.Size.Height)
        $options.DestinationWidth=[uint32][Math]::Round($page.Size.Width*$scale)
        $options.DestinationHeight=[uint32][Math]::Round($page.Size.Height*$scale)
        $action=$page.RenderToStreamAsync($stream,$options)
        $task=$actionMethod.Invoke($null,@($action))
        if(-not $task.Wait(120000)) { throw 'Render timeout' }
        $null=$task.GetAwaiter().GetResult()
        $reader=[System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
        $output=[IO.File]::Create($png)
        try { $reader.Position=0; $reader.CopyTo($output) } finally { $output.Dispose(); $reader.Dispose() }
        [Raster]::Convert($png,$pbm)
        & "$PSScriptRoot/Lbp810Usb.exe" --validate-pbm $pbm
        if($LASTEXITCODE -ne 0) { throw "Invalid raster page $($i+1)" }
        if(-not $DryRun) {
            & "$PSScriptRoot/Lbp810Usb.exe" --print-pbm $pbm
            if($LASTEXITCODE -ne 0) { throw "USB printing failed at page $($i+1). No automatic retry: earlier pages may already be printed." }
            Remove-Item -LiteralPath $png,$pbm
        }
        "Page $($i+1) processed; DryRun=$DryRun"
    } finally { $stream.Dispose(); $page.Dispose() }
}
