param([string]$ConfigPath = "$PSScriptRoot\config.local.json")
. "$PSScriptRoot\scripts\Common.ps1"
Assert-Administrator
if (-not ('CampusDns' -as [type])) { Add-Type -Path "$PSScriptRoot\scripts\CampusDns.cs" }
$config = Read-CampusConfig $ConfigPath
$statePath = "$PSScriptRoot\runtime\state.json"
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $state.connected) { throw 'Connect native OpenConnect first.' }
$adapter = Get-NetAdapter -InterfaceIndex $state.interfaceIndex
if ($adapter.Name -ne $config.interfaceName -or $adapter.Status -ne 'Up') { throw 'Native campus interface is not up.' }
$newDomains = @()
foreach ($hostName in $config.hosts) {
    $answers = @()
    foreach ($dnsServer in $state.dns) {
        try {
            $answers = @([CampusDns]::Resolve($hostName,$dnsServer,$state.address))
            if ($answers.Count) { break }
        } catch { Write-Warning "Could not resolve $hostName with campus DNS $dnsServer" }
    }
    if (-not $answers.Count) { throw "Required campus host could not be resolved: $hostName" }
    foreach ($ip in $answers) {
        $prefix = "$ip/32"
        Assert-CampusPrefix $prefix
        if (-not (Get-NetRoute -InterfaceIndex $state.interfaceIndex -DestinationPrefix $prefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
            New-NetRoute -InterfaceIndex $state.interfaceIndex -DestinationPrefix $prefix -NextHop '0.0.0.0' -RouteMetric 3 -PolicyStore ActiveStore | Out-Null
            $state.addedRoutes += $prefix
            Save-CampusState $state $statePath
        }
    }
    $newDomains += [pscustomobject]@{hostName=$hostName;addresses=$answers}
}
$state.domains = $newDomains
Save-CampusState $state $statePath
Write-Host 'Campus DNS and configured host routes ready.'
