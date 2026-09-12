param([string]$Dotnet = 'dotnet', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & $Dotnet restore BiliRemote.slnx
    if ($LASTEXITCODE -ne 0) { throw 'Restore failed' }
    if (-not $SkipTests) {
        & $Dotnet test tests/BiliRemote.Tests -c Release --no-restore
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
        & $Dotnet run --project tests/BiliRemote.Integration -c Release --no-restore -- --soak-seconds 10
        if ($LASTEXITCODE -ne 0) { throw 'Transport integration tests failed' }
        npm.cmd ci --prefix extension --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw 'npm restore failed' }
        npm.cmd run typecheck --prefix extension
        if ($LASTEXITCODE -ne 0) { throw 'Typecheck failed' }
        npm.cmd test --prefix extension
        if ($LASTEXITCODE -ne 0) { throw 'Extension tests failed' }
    }
    npm.cmd run build --prefix extension
    if ($LASTEXITCODE -ne 0) { throw 'Extension build failed' }
    & $Dotnet publish desktop/BiliRemote.Host -c Release -r win-x64 --self-contained true -o artifacts/windows -p:DebugType=None -p:DebugSymbols=false
    if ($LASTEXITCODE -ne 0) { throw 'Host publish failed' }
    & $Dotnet publish desktop/BiliRemote.Native -c Release -r win-x64 --self-contained true -o artifacts/native -p:DebugType=None -p:DebugSymbols=false
    if ($LASTEXITCODE -ne 0) { throw 'Native host publish failed' }
    New-Item -ItemType Directory -Force artifacts/windows/native, artifacts/windows/extension | Out-Null
    Copy-Item -Path artifacts/native/* -Destination artifacts/windows/native -Recurse -Force
    Copy-Item -Path extension/dist/* -Destination artifacts/windows/extension -Recurse -Force
    Copy-Item -LiteralPath README.md -Destination artifacts/windows/README.md -Force
    Copy-Item -LiteralPath scripts/install-portable.ps1 -Destination artifacts/windows/install.ps1 -Force
    Compress-Archive -Path artifacts/windows/* -DestinationPath artifacts/BiliRemote-Windows.zip -Force
    Compress-Archive -Path extension/dist/* -DestinationPath artifacts/BiliRemote-Chrome.zip -Force
    $compiler = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { $compiler = 'C:\Program Files\Inno Setup 6\ISCC.exe' }
    if (Test-Path -LiteralPath $compiler) {
        & $compiler installer/BiliRemote.iss
        if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
    } else { Write-Output 'Inno Setup is unavailable. Portable Windows installation package was generated.' }
} finally { Pop-Location }
