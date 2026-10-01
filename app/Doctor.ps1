param([string]$ConfigPath = "$PSScriptRoot\..\config.local.json")
$ProjectRoot = Split-Path $PSScriptRoot -Parent
. "$ProjectRoot\scripts\Clash.ps1"
$issues = @()
$config = $null
try { $config = Read-CampusConfig $ConfigPath; Write-Host '[OK] Local configuration' }
catch { $issues += $_.Exception.Message }
$binary = "$ProjectRoot\vendor\openconnect\openconnect.exe"
if (Test-Path -LiteralPath $binary) { Write-Host '[OK] Portable OpenConnect' } else { $issues += 'Run app\Setup.ps1: OpenConnect missing.' }
if ((Test-Path -LiteralPath "$ProjectRoot\bin\campus-config.exe") -or (Test-Path -LiteralPath "$ProjectRoot\target\release\campus-config.exe")) {
    Write-Host '[OK] Rust configuration helper'
} else { $issues += 'Use a packaged release or run tools\Build.ps1: configuration helper missing.' }
if ($config) {
    try { Assert-ClashHealth $config.clashPipe $config.clashProxyPort; Write-Host '[OK] Clash rule mode, TUN and proxy port' }
    catch { $issues += $_.Exception.Message }
}
try { Assert-Administrator; Write-Host '[OK] Administrator privilege' }
catch { Write-Host '[INFO] Current shell is not Administrator; Start.cmd will request elevation.' }
if ($issues.Count) {
    foreach ($issue in $issues) { Write-Host "[FAIL] $issue" -ForegroundColor Red }
    exit 1
}
Write-Host 'Preflight passed. Actual campus authentication/connectivity still requires a live connection.'
