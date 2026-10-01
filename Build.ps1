$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    cargo build --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed.' }
    New-Item -ItemType Directory -Path "$PSScriptRoot\bin" -Force | Out-Null
    Copy-Item -LiteralPath "$PSScriptRoot\target\release\campus-config.exe" -Destination "$PSScriptRoot\bin\campus-config.exe"
    Copy-Item -LiteralPath "$PSScriptRoot\target\release\tongji-vpn-launcher.exe" -Destination "$PSScriptRoot\bin\TongjiVPN.exe"
    Copy-Item -LiteralPath "$PSScriptRoot\bin\TongjiVPN.exe" -Destination "$PSScriptRoot\TongjiVPN.exe"
    Write-Host 'Rust configuration helper built.'
} finally { Pop-Location }
