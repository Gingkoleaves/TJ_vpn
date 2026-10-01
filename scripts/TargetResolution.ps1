function Get-CampusDnsAnswers([string]$HostName,[string]$Server,[string]$Source) {
    return [CampusDns]::Resolve($HostName,$Server,$Source)
}

function ConvertFrom-PublicDnsResponse($Response) {
    if ([int]$Response.Status -ne 0) {
        if ([int]$Response.Status -eq 3) { throw 'Public DNS returned NXDOMAIN: this name is not present in public DNS.' }
        throw "Public DNS returned status $($Response.Status)."
    }
    $answers=@()
    if ($Response.PSObject.Properties['Answer']) {
        foreach ($record in $Response.Answer) {
            if ([int]$record.type -eq 1) { Assert-CampusPrefix "$($record.data)/32"; $answers += [string]$record.data }
        }
    }
    if (-not $answers.Count) { throw 'Public DNS returned no usable IPv4 address.' }
    return @($answers | Select-Object -Unique)
}

function Get-PublicDnsAnswers([string]$HostName,[int]$ProxyPort) {
    $encoded=[Uri]::EscapeDataString($HostName)
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $options=@{Uri="https://dns.google/resolve?name=$encoded&type=A";TimeoutSec=8;ErrorAction='Stop'}
    if ($ProxyPort -gt 0) { $options.Proxy="http://127.0.0.1:$ProxyPort" }
    if ($ProxyPort -gt 0) { $response=Invoke-RestMethod @options }
    else {
        $request=[Net.HttpWebRequest]::Create($options.Uri)
        $request.Proxy=$null; $request.Timeout=8000; $request.ReadWriteTimeout=8000
        $reply=$request.GetResponse()
        try {
            $reader=[IO.StreamReader]::new($reply.GetResponseStream())
            try { $response=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        } finally { $reply.Dispose() }
    }
    return ConvertFrom-PublicDnsResponse $response
}

function Get-ReferenceCampusAnswers([string]$HostName) {
    $referencePath=Join-Path $PSScriptRoot '..\config.hosts.local.json'
    if (-not (Test-Path -LiteralPath $referencePath)) { return @() }
    $reference=Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $record=$reference.hosts.PSObject.Properties[$HostName]
    if (-not $record) { return @() }
    $addresses=@($record.Value)
    foreach ($address in $addresses) { Assert-CampusPrefix "$address/32" }
    return $addresses
}

function Resolve-CampusTarget([string]$HostName,$State,$Config) {
    $errors=@()
    foreach ($server in $State.dns) {
        try {
            $answers=@(Get-CampusDnsAnswers $HostName $server $State.address)
            if (-not $answers.Count) { throw 'No IPv4 answers.' }
            foreach ($ip in $answers) { Assert-CampusPrefix "$ip/32" }
            return [pscustomobject]@{hostName=$HostName;addresses=$answers;dnsSource='campus';error=$null}
        } catch { $errors += "Campus DNS ${server}: $($_.Exception.GetBaseException().Message)" }
    }
    try {
        $port=$Config.clashProxyPort
        if ($Config.PSObject.Properties['connectionMode'] -and $Config.connectionMode -eq 'direct') { $port=0 }
        $answers=@(Get-PublicDnsAnswers $HostName $port)
        if (-not $answers.Count) { throw 'No IPv4 answers.' }
        return [pscustomobject]@{hostName=$HostName;addresses=$answers;dnsSource='public';error=$null}
    } catch { $errors += "Public DNS: $($_.Exception.GetBaseException().Message)" }
    $reference=@(Get-ReferenceCampusAnswers $HostName)
    if ($reference.Count) {
        return [pscustomobject]@{hostName=$HostName;addresses=$reference;dnsSource='reference-pdf';error=($errors -join '; ')}
    }
    return [pscustomobject]@{hostName=$HostName;addresses=@();dnsSource='unresolved';error=($errors -join '; ')}
}

function Test-CampusSshNode([string]$Address,[string]$Source) {
    $client=$null
    try {
        $client=[Net.Sockets.TcpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Parse($Source),0))
        $pending=$client.ConnectAsync([Net.IPAddress]::Parse($Address),10022)
        if (-not $pending.Wait(1500)) { return $false }
        $stream=$client.GetStream(); $stream.ReadTimeout=1500
        $bytes=[byte[]]::new(256); $length=$stream.Read($bytes,0,$bytes.Length)
        return [Text.Encoding]::ASCII.GetString($bytes,0,$length).StartsWith('SSH-')
    } catch { return $false } finally { if ($client) { $client.Dispose() } }
}

function Select-CampusReachableNodes($Resolved,[string]$Source) {
    # Only probe hosts explicitly maintained in the user's local HPC reference.
    if (-not @(Get-ReferenceCampusAnswers $Resolved.hostName).Count) { return }
    $reachable=@($Resolved.addresses | Where-Object { Test-CampusSshNode $_ $Source })
    if ($reachable.Count) { $Resolved.addresses=$reachable }
    else { Write-Warning 'No SSH greeting received from the configured HPC pool; retaining DNS answers for retry.' }
}
