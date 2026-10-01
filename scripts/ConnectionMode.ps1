. "$PSScriptRoot\Clash.ps1"

function Read-ConnectionSettings([string]$Path) {
    $settings=[pscustomobject]@{mode='auto';mihomoPath='';clashDirectory="$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev";clashPipe='verge-mihomo';clashProxyPort=7897}
    if (Test-Path -LiteralPath $Path) {
        $saved=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @('mode','mihomoPath','clashDirectory','clashPipe','clashProxyPort')) {
            if ($saved.PSObject.Properties[$name]) { $settings.$name=$saved.$name }
        }
    }
    if ($settings.mode -notin @('auto','direct','clash')) { throw 'Invalid connection mode.' }
    if ($settings.clashPipe -notmatch '^[A-Za-z0-9_-]+$' -or $settings.clashProxyPort -lt 1 -or $settings.clashProxyPort -gt 65535) { throw 'Invalid controller settings.' }
    return $settings
}

function Get-ProxyPresence([string]$PipeName,[int]$Port) {
    if (@(Get-Process -Name clash-verge,mihomo,verge-mihomo,clash,clash-meta -ErrorAction SilentlyContinue).Count) { return $true }
    if (Test-Path -LiteralPath "\\.\pipe\$PipeName") { return $true }
    $client=[Net.Sockets.TcpClient]::new()
    try { return $client.ConnectAsync('127.0.0.1',$Port).Wait(300) -and $client.Connected }
    catch { return $false } finally { $client.Dispose() }
}

function Resolve-ConnectionMode($Settings) {
    $present=Get-ProxyPresence $Settings.clashPipe $Settings.clashProxyPort
    if ($Settings.mode -eq 'direct') {
        if ($present) { throw '检测到正在运行的代理。为避免 TUN 拦截校园流量，请使用代理联动；程序不会关闭现有代理。' }
        return [pscustomobject]@{mode='direct';mihomoPath='';message='未检测到运行中的代理，将使用校园 VPN 直连。'}
    }
    if ($Settings.mode -eq 'auto' -and -not $present) {
        return [pscustomobject]@{mode='direct';mihomoPath='';message='未检测到运行中的代理，将使用校园 VPN 直连。'}
    }
    $kernel=Find-Mihomo $Settings.mihomoPath
    Assert-MihomoBinary $kernel
    Assert-ClashHealth $Settings.clashPipe $Settings.clashProxyPort
    foreach ($relative in @('clash-verge.yaml','profiles\Script.js')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Settings.clashDirectory $relative) -PathType Leaf)) { throw "代理联动配置缺失：$relative。请在代理设置中选择 Clash Verge 配置目录。" }
    }
    return [pscustomobject]@{mode='clash';mihomoPath=$kernel;message='代理联动可用；保留当前 Clash 与外网代理。'}
}

function Assert-MihomoBinary([string]$Path) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$Path; $info.Arguments='-v'; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(3000)) { $process.Kill(); throw '内核版本检测超时。' }
        if ($process.ExitCode -ne 0 -or ($stdout.Result+$stderr.Result) -notmatch '(?i)mihomo') { throw '所选文件不是可用的 mihomo 内核。' }
    } finally { $process.Dispose() }
}
