. "$PSScriptRoot\scripts\Common.ps1"
$statePath = "$PSScriptRoot\runtime\state.json"
if (-not (Test-Path -LiteralPath $statePath)) { Write-Host 'No native campus connection has been configured yet.'; exit 0 }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
$state | Select-Object connected,interfaceName,address,dns,connectedAt,error | Format-List
Get-NetAdapter -Name $state.interfaceName -ErrorAction SilentlyContinue | Select-Object Name,Status,InterfaceDescription
Get-NetRoute -InterfaceIndex $state.interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object DestinationPrefix,NextHop,RouteMetric
