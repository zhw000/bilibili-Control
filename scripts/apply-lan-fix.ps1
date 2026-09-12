param([Parameter(Mandatory = $true)][string]$InstallationDirectory)
$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path -LiteralPath $InstallationDirectory).Path
$helperExe = Join-Path $installRoot 'BiliRemote.exe'
if (-not (Test-Path -LiteralPath $helperExe -PathType Leaf)) { throw 'Select the installed BiliRemote directory.' }
$patchNames = @('BiliRemote.dll', 'BiliRemote.Core.dll')
foreach ($patchName in $patchNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $patchName) -PathType Leaf)) { throw "Missing patch component: $patchName" }
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot $patchName) -PathType Leaf)) { throw "Invalid installation: $patchName" }
}
$backupPath = Join-Path $installRoot ('backup-lan-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupPath | Out-Null
foreach ($patchName in $patchNames) { Copy-Item -LiteralPath (Join-Path $installRoot $patchName) -Destination (Join-Path $backupPath $patchName) }
$runningHelpers = @(Get-CimInstance Win32_Process -Filter "Name='BiliRemote.exe'" | Where-Object { $_.ExecutablePath -eq $helperExe })
foreach ($helper in $runningHelpers) {
    $process = Get-Process -Id $helper.ProcessId
    Stop-Process -Id $helper.ProcessId -Force
    if (-not $process.WaitForExit(10000)) { throw 'The previous helper has not exited.' }
}
foreach ($patchName in $patchNames) {
    $sourcePath = Join-Path $PSScriptRoot $patchName
    $targetPath = Join-Path $installRoot $patchName
    $copied = $false
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        try { Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force; $copied = $true; break }
        catch [System.IO.IOException] { Start-Sleep -Milliseconds 200 }
    }
    if (-not $copied) { throw "Cannot update $patchName. Original files are in $backupPath" }
    if ((Get-FileHash -LiteralPath $sourcePath).Hash -ne (Get-FileHash -LiteralPath $targetPath).Hash) { throw "Verification failed: $patchName" }
}
Start-Process -FilePath $helperExe -WorkingDirectory $installRoot -WindowStyle Hidden
Write-Output 'LAN selection fix installed. Refresh the pairing QR code and scan it again on the iPhone.'
Write-Output "Backup: $backupPath"
