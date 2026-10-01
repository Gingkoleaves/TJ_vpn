param([Parameter(Mandatory=$true)][string]$ConfigPath)
. "$PSScriptRoot\Common.ps1"
$repoRoot = Split-Path $PSScriptRoot -Parent
$runtime = Join-Path $repoRoot 'runtime'
$statePath = Join-Path $runtime 'state.json'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null

try {
    $config = Read-CampusConfig $ConfigPath
    if ($env:reason -eq 'pre-init') { exit 0 }
    if ($env:reason -eq 'disconnect') {
        Remove-CampusState $statePath
        Write-Host 'Campus routes removed; external routing retained.'
        exit 0
    }
    if ($env:reason -notin @('connect', 'reconnect')) { exit 0 }
    Assert-Administrator
    $interfaceIndex = [int]$env:TUNIDX
    $adapter = Get-NetAdapter -InterfaceIndex $interfaceIndex
    if (-not (Test-CampusAdapter $adapter $config.interfaceName)) {
        throw 'Refusing to configure an unexpected network adapter.'
    }
    $address = [Net.IPAddress]::Parse($env:INTERNAL_IP4_ADDRESS)
    if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'IPv4 is required.' }
    $dns = @($env:INTERNAL_IP4_DNS -split '\s+' | Where-Object { $_ })
    if ($dns.Count -eq 0) { throw 'VPN did not provide campus DNS servers.' }
    foreach ($ip in $dns) { Assert-CampusPrefix "$ip/32" }
    Remove-CampusState $statePath
    $state = [pscustomobject]@{
        connected = $false; interfaceIndex = $interfaceIndex; interfaceName = $config.interfaceName
        address = $address.ToString(); dns = $dns; addedRoutes = @(); addedAddress = $false
        connectedAt = (Get-Date).ToString('o'); domains = @(); error = $null
    }
    Save-CampusState $state $statePath
    Set-NetIPInterface -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -Dhcp Disabled -AutomaticMetric Disabled -InterfaceMetric 50
    if ($env:INTERNAL_IP4_MTU) {
        Set-NetIPInterface -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -NlMtuBytes ([int]$env:INTERNAL_IP4_MTU)
    }
    if (-not (Get-NetIPAddress -InterfaceIndex $interfaceIndex -IPAddress $address -ErrorAction SilentlyContinue)) {
        New-NetIPAddress -InterfaceIndex $interfaceIndex -IPAddress $address -PrefixLength 32 -PolicyStore ActiveStore | Out-Null
        $state.addedAddress = $true
        Save-CampusState $state $statePath
    }
    function Add-CampusRoute([string]$Prefix) {
        Assert-CampusPrefix $Prefix
        if (-not (Get-NetRoute -InterfaceIndex $interfaceIndex -DestinationPrefix $Prefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
            New-NetRoute -InterfaceIndex $interfaceIndex -DestinationPrefix $Prefix -NextHop '0.0.0.0' -RouteMetric 3 -PolicyStore ActiveStore | Out-Null
            $state.addedRoutes += $Prefix
            Save-CampusState $state $statePath
        }
    }
    foreach ($prefix in $config.routes) { Add-CampusRoute $prefix }
    foreach ($ip in $dns) { Add-CampusRoute "$ip/32" }
    # OpenConnect gives Windows hooks a 10-second deadline. DNS and Clash work
    # run in the parent supervisor AFTER this short interface hook returns.
    if (Get-NetRoute -InterfaceIndex $interfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue) {
        throw 'Unexpected VPN default route; refusing to mark connection ready.'
    }
    $state.connected = $true
    Save-CampusState $state $statePath
    Write-Host 'Native campus interface configured. Server default route ignored; system DNS unchanged.'
    exit 0
} catch {
    $message = $_.Exception.Message
    [IO.File]::WriteAllText((Join-Path $runtime 'hook-error.txt'), $message, [Text.UTF8Encoding]::new($false))
    Write-Error $message -ErrorAction Continue
    if (Test-Path -LiteralPath $statePath) {
        Remove-CampusState $statePath
        $failedState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $failedState.error = $message
        Save-CampusState $failedState $statePath
    }
    exit 1
}
