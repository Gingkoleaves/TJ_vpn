. "$PSScriptRoot\scripts\Common.ps1"
$statePath=Join-Path $PSScriptRoot 'runtime\state.json'
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $state.connected) { throw 'Connect campus VPN before testing HPC nodes.' }
$adapter=Get-NetAdapter -InterfaceIndex $state.interfaceIndex -ErrorAction SilentlyContinue
if (-not (Test-CampusAdapter $adapter $state.interfaceName) -or $adapter.Status -ne 'Up') { throw 'Campus adapter is not up.' }
$results=@()
foreach ($domain in @($state.domains)) {
    foreach ($address in $domain.addresses) {
        $client=$null; $success=$false; $banner=''; $errorMessage=''
        try {
            $endpoint=[Net.IPEndPoint]::new([Net.IPAddress]::Parse($state.address),0)
            $client=[Net.Sockets.TcpClient]::new($endpoint)
            $connect=$client.ConnectAsync([Net.IPAddress]::Parse($address),10022)
            if (-not $connect.Wait(2500)) { throw 'TCP connection timed out.' }
            $stream=$client.GetStream(); $stream.ReadTimeout=2000
            $bytes=[byte[]]::new(256)
            $count=$stream.Read($bytes,0,$bytes.Length)
            $banner=[Text.Encoding]::ASCII.GetString($bytes,0,$count).Trim()
            $success=$banner -match '^SSH-'
            if (-not $success) { $errorMessage='Port accepted connection but no SSH greeting received.' }
        } catch { $errorMessage=$_.Exception.GetBaseException().Message }
        finally { if ($client) { $client.Dispose() } }
        $record=[pscustomobject]@{hostName=$domain.hostName;address=$address;port=10022;sshGreeting=$success;banner=$banner;error=$errorMessage}
        $results+=$record
        Write-Host "$($domain.hostName) ${address}:10022 SSH greeting=$success $errorMessage"
    }
}
if (-not $results.Count) { throw 'Configure a campus domain and reconnect first.' }
$results | Export-Csv -LiteralPath "$PSScriptRoot\runtime\hpc-checks.csv" -NoTypeInformation -Encoding UTF8
if (-not @($results | Where-Object sshGreeting).Count) { exit 1 }
