Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-CampusConfig([string]$Path) {
    $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $uri = [Uri]$config.server
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') {
        throw 'server must be an HTTPS origin without credentials, query or path.'
    }
    if ($config.interfaceName -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,30}$') { throw 'Invalid interfaceName.' }
    if ($config.clashProxyName -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,40}$') { throw 'Invalid clashProxyName.' }
    foreach ($prefix in $config.routes) { Assert-CampusPrefix $prefix }
    foreach ($hostName in @($config.hosts) + @($config.domainSuffixes)) {
        if ($hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$') { throw "Invalid domain: $hostName" }
    }
    return $config
}

function Assert-CampusPrefix([string]$Prefix) {
    $parts = $Prefix.Split('/')
    $parsedIp = $null
    $length = 0
    if ($parts.Count -ne 2 -or -not [Net.IPAddress]::TryParse($parts[0], [ref]$parsedIp) -or
        $parsedIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        -not [int]::TryParse($parts[1], [ref]$length) -or $length -lt 8 -or $length -gt 32) {
        throw "Invalid or overly broad IPv4 route: $Prefix (allowed /8 to /32)."
    }
    $bytes = $parsedIp.GetAddressBytes()
    if ($bytes[0] -eq 0 -or $bytes[0] -eq 127 -or $bytes[0] -ge 224 -or
        ($bytes[0] -eq 198 -and $bytes[1] -in 18,19)) { throw "Reserved route refused: $Prefix" }
    for ($bit = $length; $bit -lt 32; $bit++) {
        if (($bytes[[int][Math]::Floor($bit / 8)] -band (1 -shl (7 - ($bit % 8)))) -ne 0) {
            throw "Route must use a network address: $Prefix"
        }
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in an Administrator PowerShell: Wintun and route configuration require it.'
    }
}

function Save-CampusState($State, [string]$Path) {
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Remove-CampusState([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $adapter = Get-NetAdapter -InterfaceIndex $state.interfaceIndex -ErrorAction SilentlyContinue
    if ($adapter -and $adapter.Name -eq $state.interfaceName -and $adapter.InterfaceDescription -like '*Wintun*') {
        foreach ($route in @($state.addedRoutes)) {
            Get-NetRoute -InterfaceIndex $state.interfaceIndex -DestinationPrefix $route -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -eq '0.0.0.0' -and $_.RouteMetric -eq 3 } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
        if ($state.addedAddress) {
            Get-NetIPAddress -InterfaceIndex $state.interfaceIndex -IPAddress $state.address -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    # Leave a record for status/recovery; it contains no credentials or cookies.
    $state.connected = $false
    Save-CampusState $state $Path
}
