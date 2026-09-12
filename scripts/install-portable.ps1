$ErrorActionPreference = 'Stop'
$taskNativeExe = Join-Path $PSScriptRoot 'native\BiliRemote.Native.exe'
if (-not (Test-Path -LiteralPath $taskNativeExe)) { throw 'Extract the complete Windows package before installation.' }
$taskManifest = Join-Path $PSScriptRoot 'native\com.biliremote.bridge.json'
$taskDescription = @{name='com.biliremote.bridge';description='Bili Remote Chrome bridge';path=$taskNativeExe;type='stdio';allowed_origins=@('chrome-extension://penfpdlcbljgooeeabnkphfggjhbfnnj/')}
[System.IO.File]::WriteAllText($taskManifest,($taskDescription | ConvertTo-Json -Depth 3),[System.Text.UTF8Encoding]::new($false))
$taskKey = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.biliremote.bridge'
New-Item -Path $taskKey -Force | Out-Null
Set-Item -Path $taskKey -Value $taskManifest
Write-Output 'Registered the Chrome bridge for the current user. Keep this folder in place.'
Write-Output 'Start BiliRemote.exe, then load the extension folder in chrome://extensions.'
