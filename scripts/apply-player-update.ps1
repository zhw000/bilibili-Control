param(
    [Parameter(Mandatory = $true)][string]$InstallationDirectory,
    [Parameter(Mandatory = $true)][string]$ExtensionDirectory
)
$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path -LiteralPath $InstallationDirectory).Path
$extensionRoot = (Resolve-Path -LiteralPath $ExtensionDirectory).Path
$helperExe = Join-Path $installRoot 'BiliRemote.exe'
if (-not (Test-Path -LiteralPath $helperExe -PathType Leaf)) { throw 'Select the installed BiliRemote directory.' }
$sourceExtension = Join-Path $PSScriptRoot 'extension'
$sourceManifest = Get-Content -LiteralPath (Join-Path $sourceExtension 'manifest.json') -Raw | ConvertFrom-Json
$targetManifest = Get-Content -LiteralPath (Join-Path $extensionRoot 'manifest.json') -Raw | ConvertFrom-Json
if (-not $sourceManifest.key -or $sourceManifest.key -ne $targetManifest.key) { throw 'The selected extension directory belongs to a different extension.' }
$componentNames = @('BiliRemote.dll', 'BiliRemote.Core.dll')
foreach ($name in $componentNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name)) -or -not (Test-Path -LiteralPath (Join-Path $installRoot $name))) { throw "Missing component: $name" }
}
$backupPath = Join-Path $installRoot ('backup-player-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupPath | Out-Null
foreach ($name in $componentNames) { Copy-Item -LiteralPath (Join-Path $installRoot $name) -Destination $backupPath }
$extensionBackup = Join-Path $backupPath 'extension'
New-Item -ItemType Directory -Path $extensionBackup | Out-Null
Get-ChildItem -LiteralPath $extensionRoot -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $extensionBackup }
$helpers = @(Get-CimInstance Win32_Process -Filter "Name='BiliRemote.exe'" | Where-Object { $_.ExecutablePath -eq $helperExe })
foreach ($helper in $helpers) {
    $process = Get-Process -Id $helper.ProcessId
    Stop-Process -Id $helper.ProcessId -Force
    if (-not $process.WaitForExit(10000)) { throw 'The previous helper has not exited.' }
}
foreach ($name in $componentNames) {
    $source = Join-Path $PSScriptRoot $name
    $target = Join-Path $installRoot $name
    $copied = $false
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        try { Copy-Item -LiteralPath $source -Destination $target -Force; $copied = $true; break }
        catch [System.IO.IOException] { Start-Sleep -Milliseconds 200 }
    }
    if (-not $copied) { throw "Cannot update $name. Backup: $backupPath" }
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Verification failed: $name" }
}
foreach ($file in Get-ChildItem -LiteralPath $sourceExtension -File) {
    $destination = Join-Path $extensionRoot $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Extension verification failed: $($file.Name)" }
}
Start-Process -FilePath $helperExe -WorkingDirectory $installRoot -WindowStyle Hidden
Write-Output 'Desktop update installed. Reload the Bili Remote extension in Chrome, then refresh the Bilibili playback page.'
Write-Output "Backup: $backupPath"
