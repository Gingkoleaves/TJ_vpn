. "$PSScriptRoot\Common.ps1"

function ConvertFrom-ClashResponse([byte[]]$Bytes) {
    $text = [Text.Encoding]::UTF8.GetString($Bytes)
    $separator = $text.IndexOf("`r`n`r`n")
    if ($separator -lt 0 -or $text -notmatch '^HTTP/1\.[01] (\d{3})') { throw 'Invalid Clash HTTP response.' }
    $status = [int]$Matches[1]
    $headers = $text.Substring(0, $separator)
    $offset = $separator + 4
    if ($headers -match '(?im)^Transfer-Encoding:\s*chunked') {
        $decoded = [IO.MemoryStream]::new()
        try {
            $complete = $false
            while ($offset -lt $Bytes.Length) {
                $lineEnd = $offset
                while ($lineEnd + 1 -lt $Bytes.Length -and -not ($Bytes[$lineEnd] -eq 13 -and $Bytes[$lineEnd + 1] -eq 10)) { $lineEnd++ }
                if ($lineEnd + 1 -ge $Bytes.Length) { throw 'Invalid chunked response.' }
                $line = [Text.Encoding]::ASCII.GetString($Bytes, $offset, $lineEnd - $offset)
                $size = [Convert]::ToInt32($line.Split(';')[0], 16)
                if ($size -lt 0) { throw 'Invalid chunk size.' }
                $offset = $lineEnd + 2
                if ($size -eq 0) { $complete = $true; break }
                if ($Bytes.Length - $offset -lt $size + 2) { throw 'Incomplete chunked response.' }
                $decoded.Write($Bytes, $offset, $size)
                $offset += $size
                if ($Bytes[$offset] -ne 13 -or $Bytes[$offset + 1] -ne 10) { throw 'Invalid chunk delimiter.' }
                $offset += 2
            }
            if (-not $complete) { throw 'Missing final HTTP chunk.' }
            $content = [Text.Encoding]::UTF8.GetString($decoded.ToArray())
        } finally { $decoded.Dispose() }
    } else {
        if ($headers -match '(?im)^Content-Length:\s*(\d+)') {
            if ($Bytes.Length - $offset -ne [int]$Matches[1]) { throw 'Incomplete Clash HTTP body.' }
        }
        $content = [Text.Encoding]::UTF8.GetString($Bytes, $offset, $Bytes.Length - $offset)
    }
    if ($status -lt 200 -or $status -ge 300) { throw "Clash controller HTTP $status`: $content" }
    if ($content.Trim()) { return ($content | ConvertFrom-Json) }
    return $null
}

function Invoke-ClashPipe([string]$PipeName, [string]$Method, [string]$Path, $Body = $null) {
    if ($PipeName -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid local Clash pipe name.' }
    if ($Method -notin @('GET','PUT','PATCH') -or $Path -notmatch '^/[A-Za-z0-9_/?=&%-]*$') { throw 'Invalid controller request.' }
    $bodyText = if ($null -eq $Body) { '' } else { ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($bodyText)
    $header = "$Method $Path HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`nContent-Type: application/json`r`nContent-Length: $($bodyBytes.Length)`r`n`r`n"
    $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    $output = [IO.MemoryStream]::new()
    try {
        $pipe.Connect(5000)
        $request = [Text.Encoding]::UTF8.GetBytes($header + $bodyText)
        if (-not $pipe.WriteAsync($request, 0, $request.Length).Wait(5000)) { throw 'Clash controller write timeout.' }
        $buffer = New-Object byte[] 8192
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while ($watch.Elapsed.TotalSeconds -lt 20) {
            $task = $pipe.ReadAsync($buffer, 0, $buffer.Length)
            if (-not $task.Wait(5000)) { throw 'Clash controller read timeout.' }
            $count = $task.Result
            if ($count -eq 0) { break }
            $output.Write($buffer, 0, $count)
            if ($output.Length -gt 2097152) { throw 'Clash controller response too large.' }
        }
        if ($watch.Elapsed.TotalSeconds -ge 20) { throw 'Clash controller response deadline exceeded.' }
        return (ConvertFrom-ClashResponse $output.ToArray())
    } finally { $output.Dispose(); $pipe.Dispose() }
}

function Find-Mihomo([string]$ExplicitPath) {
    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) { throw 'Mihomo path does not exist.' }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    $verge = Get-Process -Name clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($verge -and $verge.Path) {
        $candidate = Join-Path (Split-Path $verge.Path -Parent) 'verge-mihomo.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'Could not locate Mihomo. Supply -MihomoPath <verge-mihomo.exe>.'
}

function Assert-ClashHealth([string]$PipeName, [int]$Port) {
    $settings = Invoke-ClashPipe $PipeName GET '/configs'
    if ($settings.mode -ne 'rule') { throw 'Clash must be in rule mode; the script does not change your mode.' }
    if (-not $settings.tun.enable) { throw 'Clash TUN must remain enabled for Windows SSH capture.' }
    $client = [Net.Sockets.TcpClient]::new()
    try {
        if (-not $client.ConnectAsync('127.0.0.1', $Port).Wait(3000)) { throw 'Clash proxy port not available.' }
    } finally { $client.Dispose() }
}

function Get-ClashSelections([string]$PipeName) {
    $response = Invoke-ClashPipe $PipeName GET '/proxies'
    return @($response.proxies.PSObject.Properties | Where-Object { $_.Value.type -eq 'Selector' } |
        ForEach-Object { [pscustomobject]@{name=$_.Name; selected=$_.Value.now} })
}

function Restore-ClashSelections([string]$PipeName, $Selections) {
    $response = Invoke-ClashPipe $PipeName GET '/proxies'
    foreach ($selection in @($Selections)) {
        $property = $response.proxies.PSObject.Properties[$selection.name]
        if (-not $property -or $property.Value.type -ne 'Selector' -or $property.Value.all -notcontains $selection.selected) {
            throw "Existing external proxy selection cannot be preserved: $($selection.name)"
        }
        if ($property.Value.now -ne $selection.selected) {
            $encoded = [Uri]::EscapeDataString($selection.name)
            Invoke-ClashPipe $PipeName PUT "/proxies/$encoded" @{name=$selection.selected} | Out-Null
        }
    }
}
