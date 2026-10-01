# Exact host entries only. Persist ownership before editing so interrupted sessions can recover.
function Set-DirectHostMappings($Domains,[string]$JournalPath,[string]$HostsPath="$env:SystemRoot\System32\drivers\etc\hosts") {
    Restore-DirectHostMappings $JournalPath $HostsPath
    $original=[IO.File]::ReadAllText($HostsPath)
    $lines=@(); $marker='TongjiVPN-'+[Guid]::NewGuid().ToString('N')
    foreach ($domain in @($Domains)) {
        if (-not @($domain.addresses).Count) { continue }
        Assert-CampusDomain $domain.hostName
        foreach ($line in ($original -split "`r?`n")) {
            $tokens=@(($line -split '#',2)[0] -split '\s+' | Where-Object { $_ })
            if ($tokens.Count -gt 1 -and @($tokens | Select-Object -Skip 1) -contains $domain.hostName) { throw "hosts 已存在 $($domain.hostName) 的映射；请通过 GUI 修改目标或先处理现有映射。" }
        }
        $address=$domain.addresses[0]; Assert-CampusPrefix "$address/32"
        $lines += "$address $($domain.hostName) # $marker"
    }
    if (-not $lines.Count) { return }
    Save-CampusState ([pscustomobject]@{active=$true;lines=$lines}) $JournalPath
    [IO.File]::AppendAllText($HostsPath,"`r`n"+($lines -join "`r`n")+"`r`n",[Text.UTF8Encoding]::new($false))
    if ($HostsPath -eq "$env:SystemRoot\System32\drivers\etc\hosts") { Clear-DnsClientCache }
}

function Restore-DirectHostMappings([string]$JournalPath,[string]$HostsPath="$env:SystemRoot\System32\drivers\etc\hosts") {
    if (-not (Test-Path -LiteralPath $JournalPath)) { return }
    $journal=Get-Content -LiteralPath $JournalPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $journal.active) { return }
    $text=[IO.File]::ReadAllText($HostsPath)
    foreach ($line in @($journal.lines)) {
        if ($line -notmatch '^([0-9.]+) ([A-Za-z0-9.-]+) # TongjiVPN-[a-f0-9]{32}$') { throw 'Invalid DNS recovery journal.' }
        Assert-CampusPrefix "$($Matches[1])/32"; Assert-CampusDomain $Matches[2]
        $text=[regex]::Replace($text,'(?m)^'+[regex]::Escape($line)+'\r?\n?','')
    }
    [IO.File]::WriteAllText($HostsPath,$text,[Text.UTF8Encoding]::new($false))
    $journal.active=$false; Save-CampusState $journal $JournalPath
    if ($HostsPath -eq "$env:SystemRoot\System32\drivers\etc\hosts") { Clear-DnsClientCache }
}
