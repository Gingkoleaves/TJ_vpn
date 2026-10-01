param([string]$ConfigPath = "$PSScriptRoot\config.local.json", $DesktopContext)
. "$PSScriptRoot\scripts\Common.ps1"
. "$PSScriptRoot\scripts\TargetResolution.ps1"
. "$PSScriptRoot\scripts\DesktopStatus.ps1"
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
    $resolved=Resolve-CampusTarget $hostName $state $config
    $answers=@($resolved.addresses)
    $newDomains += $resolved
    if (-not $answers.Count) {
        $message="Unresolved target ${hostName}; other campus targets remain enabled. $($resolved.error)"
        Write-Warning $message
        if ($DesktopContext) { Write-DesktopStatus $DesktopContext 'connecting' 'Continuing with available campus targets' @($message) }
        continue
    }
    if ($DesktopContext) { Write-DesktopStatus $DesktopContext 'connecting' 'Resolving campus targets' @("${hostName}: $($answers -join ', ') [$($resolved.dnsSource) DNS]") }
    if ($resolved.dnsSource -eq 'reference-pdf') {
        $message="${hostName}: using documented HPC fallback addresses (SSH port 10022); live DNS did not succeed. $($resolved.error)"
        Write-Warning $message
        if ($DesktopContext) { Write-DesktopStatus $DesktopContext 'connecting' 'Using documented HPC address fallback' @($message) }
    }
    foreach ($ip in $answers) {
        $prefix = "$ip/32"
        Assert-CampusPrefix $prefix
        if (-not (Get-NetRoute -InterfaceIndex $state.interfaceIndex -DestinationPrefix $prefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
            New-NetRoute -InterfaceIndex $state.interfaceIndex -DestinationPrefix $prefix -NextHop '0.0.0.0' -RouteMetric 3 -PolicyStore ActiveStore | Out-Null
            $state.addedRoutes += $prefix
            Save-CampusState $state $statePath
        }
    }
    Select-CampusReachableNodes $resolved $state.address
}
$state.domains = $newDomains
if ($DesktopContext) {
    $DesktopContext.State | Add-Member -NotePropertyName unresolvedTargets -NotePropertyValue @($newDomains | Where-Object { -not $_.addresses.Count } | ForEach-Object hostName) -Force
}
Save-CampusState $state $statePath
Write-Host 'Campus DNS and configured host routes ready.'
