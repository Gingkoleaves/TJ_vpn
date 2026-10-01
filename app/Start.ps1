$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $file = "$ProjectRoot\app\Start.ps1"
    Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $file + '"')
    return
}
try {
    if (-not (Test-Path -LiteralPath "$ProjectRoot\vendor\openconnect\openconnect.exe")) {
        Write-Host 'First start: preparing the verified OpenConnect client...'
        & "$ProjectRoot\app\Setup.ps1"
    }
    & "$ProjectRoot\app\Connect.ps1"
}
catch { Write-Host $_.Exception.Message -ForegroundColor Red }
finally { Read-Host 'Press Enter to close this window' | Out-Null }
