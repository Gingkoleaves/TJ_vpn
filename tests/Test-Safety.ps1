. "$PSScriptRoot\..\scripts\Common.ps1"
$passed = 0
function Assert-Rejected([scriptblock]$Action) {
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    if (-not $rejected) { throw 'Expected rejection did not occur.' }
    $script:passed++
}
foreach ($route in @('0.0.0.0/0','128.0.0.0/1','192.0.2.10/24','127.0.0.1/32','198.18.0.14/32','224.0.0.0/8','10.0.0.0/33','bad/32')) {
    Assert-Rejected { Assert-CampusPrefix $route }
}
foreach ($route in @('192.0.2.10/32','192.0.0.0/16','202.120.190.208/32')) { Assert-CampusPrefix $route; $passed++ }
$config = Read-CampusConfig "$PSScriptRoot\..\config.example.json"
if ($config.server -ne 'https://vpn.tongji.cn') { throw 'Example configuration failed.' }
$passed++
if ((ConvertTo-NativeArgument 'a b') -ne '"a b"') { throw 'Space argument not preserved.' }
if ((ConvertTo-NativeArgument 'a"b') -ne '"a\"b"') { throw 'Quote argument not escaped.' }
if ((ConvertTo-NativeArgument 'C:\space path\') -ne '"C:\space path\\"') { throw 'Trailing slash not escaped.' }
$passed += 3
$temporaryRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\tests'
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
$statePath = Join-Path $temporaryRoot 'state.json'
Save-CampusState ([pscustomobject]@{connected=$true;test=1}) $statePath
Save-CampusState ([pscustomobject]@{connected=$false;test=2}) $statePath
$saved = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($saved.test -ne 2 -or $saved.connected) { throw 'State replace did not commit.' }
$passed++

# Exercise recovery with mocked adapters. Never delete a route on a reused
# interface index that now belongs to another network adapter.
$script:removed = @()
function Get-NetAdapter { param($InterfaceIndex,$ErrorAction) [pscustomobject]@{Name='OtherVPN';InterfaceDescription='Wintun'} }
function Get-NetRoute { param($InterfaceIndex,$DestinationPrefix,$PolicyStore,$ErrorAction) throw 'Wrong adapter route lookup!' }
function Get-NetIPAddress { param($InterfaceIndex,$IPAddress,$ErrorAction) throw 'Wrong adapter IP lookup!' }
Save-CampusState ([pscustomobject]@{connected=$true;interfaceIndex=99;interfaceName='TongjiVPN';
    address='192.0.2.100';addedAddress=$true;addedRoutes=@('192.0.2.10/32')}) $statePath
Remove-CampusState $statePath
if ((Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).connected) { throw 'Recovery state was not updated.' }
$passed++
Write-Host "$passed safety checks passed. No real adapter or route was changed."
