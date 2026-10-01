param(
    [string]$ConfigPath = "$PSScriptRoot\..\config.local.json",
    [string]$UserName,
    [string]$ClashDirectory = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev",
    [string]$MihomoPath,
    [switch]$NoClash,
    [string]$ClashPipe,
    [int]$ClashProxyPort,
    [pscredential]$Credential,
    $DesktopContext
)
$ProjectRoot = Split-Path $PSScriptRoot -Parent
. "$ProjectRoot\scripts\Clash.ps1"
. "$ProjectRoot\scripts\DesktopStatus.ps1"
. "$ProjectRoot\scripts\DirectDns.ps1"
. "$ProjectRoot\scripts\ConnectionMode.ps1"
if ($Credential -and -not $DesktopContext) { throw 'Background credentials require an explicit desktop status context.' }
Assert-Administrator
if (-not (Test-Path -LiteralPath $ConfigPath)) { Copy-Item -LiteralPath "$ProjectRoot\config\config.example.json" -Destination $ConfigPath }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Read-CampusConfig $ConfigPath
if ($ClashPipe) { $config.clashPipe=$ClashPipe }
if ($ClashProxyPort) { $config.clashProxyPort=$ClashProxyPort }
$config | Add-Member -NotePropertyName connectionMode -NotePropertyValue $(if($NoClash){'direct'}else{'clash'}) -Force
if ($NoClash -and (Get-ProxyPresence $config.clashPipe $config.clashProxyPort)) { throw '直连模式检测到运行中的代理，请使用 GUI 代理联动。现有代理未改动。' }
if (-not $NoClash) {
    Assert-ClashHealth $config.clashPipe $config.clashProxyPort
    $MihomoPath = Find-Mihomo $MihomoPath
    if (-not (Test-Path -LiteralPath "$ProjectRoot\bin\campus-config.exe") -and
        -not (Test-Path -LiteralPath "$ProjectRoot\target\release\campus-config.exe")) { throw 'Run tools\Build.ps1 or use a packaged release.' }
}
$binary = "$ProjectRoot\vendor\openconnect\openconnect.exe"
if (-not (Test-Path -LiteralPath $binary)) { throw 'Run app\Setup.ps1 first.' }
$savedPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$version = & $binary --version 2>&1 | Out-String
$ErrorActionPreference = $savedPreference
if ($version -notmatch 'Supported protocols:.*array') { throw 'This OpenConnect build does not support Array.' }
$runtime = "$ProjectRoot\runtime"
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$lockPath = Join-Path $runtime 'connection.lock'
$lockHandle = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try { Restore-DirectHostMappings (Join-Path $runtime 'direct-dns.json') }
catch { $lockHandle.Dispose(); throw }
$baseInterfaceName = $config.interfaceName
# OpenConnect treats a stale registry match as a hard failure when Wintun
# cannot reopen it. Use a distinct name for each connection, without deleting
# or resetting any existing adapter/driver (Clash must remain online).
$config.interfaceName = New-CampusInterfaceName $baseInterfaceName
$ConfigPath = Join-Path $runtime 'session-config.json'
Save-CampusState $config $ConfigPath
$oldConfigEnv = $env:CAMPUS_CONFIG_PATH
$env:CAMPUS_CONFIG_PATH = $ConfigPath
$hook = "$ProjectRoot\scripts\vpnc-hook.js"
$arguments = @('--protocol=array', '--no-dtls', '--disable-ipv6', '--interface', $config.interfaceName, '--script', $hook)
if ($Credential) {
    $UserName=$Credential.UserName
    $arguments += @('--passwd-on-stdin','--non-inter','--form-entry=form:method=')
}
if ($UserName) { $arguments += @('--user', $UserName) }
$arguments += $config.server
Write-Host 'Keep Clash running. Leave authgroup EMPTY; enter your campus username/password locally.'
Write-Host 'Keep this terminal open. Press Ctrl+C to disconnect. No password or cookie is saved.'
Write-Host "Session adapter: $($config.interfaceName)"
$process = $null
$backgroundProcess = $null
$clashApplied = $false
$pidPath = Join-Path $runtime 'process.json'
try {
    Remove-Item -LiteralPath "$runtime\disconnect.request" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$runtime\hook-error.txt" -ErrorAction SilentlyContinue
    Remove-CampusState "$runtime\state.json"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $binary
    $info.Arguments = (($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $info.WorkingDirectory = Split-Path $binary -Parent
    $info.UseShellExecute = $false
    # The child inherits this console for hidden password entry; stdin is not captured.
    if ($Credential) {
        if (-not ('CampusBackgroundProcess' -as [type])) { Add-Type -Path "$ProjectRoot\scripts\DesktopBridge.cs" }
        $backgroundProcess=[CampusBackgroundProcess]::new($binary,$info.Arguments,$Credential.GetNetworkCredential().Password)
        $process=$backgroundProcess.Process
    } else { $process = [Diagnostics.Process]::Start($info) }
    Save-CampusState ([pscustomobject]@{id=$process.Id; path=$binary; startedAt=$process.StartTime.ToUniversalTime().ToString('o')}) $pidPath
    $lastReady = ''
    while (-not $process.HasExited) {
        if ($Credential -and (Test-Path -LiteralPath "$runtime\disconnect-background.request") -and
            (Get-Content -LiteralPath "$runtime\disconnect-background.request" -Raw) -eq $DesktopContext.State.session) { break }
        if ($backgroundProcess) { Write-DesktopStatus $DesktopContext 'connecting' 'Campus connection in progress' $backgroundProcess.Drain() }
        if (Test-Path -LiteralPath "$runtime\disconnect.request") {
            Write-Host 'Disconnect requested from the desktop panel.'
            break
        }
        if (Test-Path -LiteralPath "$runtime\hook-error.txt") {
            throw ('Campus hook failed: ' + (Get-Content -LiteralPath "$runtime\hook-error.txt" -Raw -Encoding UTF8))
        }
        $statePath = Join-Path $runtime 'state.json'
        if (Test-Path -LiteralPath $statePath) {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.error) { throw "Campus route setup failed: $($state.error)" }
            if ($state.connected -and $state.connectedAt -ne $lastReady) {
                & "$ProjectRoot\app\Update-CampusRoutes.ps1" -ConfigPath $ConfigPath -DesktopContext $DesktopContext
                $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $state | Add-Member -NotePropertyName connectionMode -NotePropertyValue $config.connectionMode -Force
                Save-CampusState $state $statePath
                if ($NoClash) { Set-DirectHostMappings $state.domains (Join-Path $runtime 'direct-dns.json') }
                if (-not $NoClash) {
                    & "$ProjectRoot\app\Apply-Clash.ps1" -ConfigPath $ConfigPath -ClashDirectory $ClashDirectory -MihomoPath $MihomoPath
                    $clashApplied = $true
                }
                $lastReady = $state.connectedAt
                if ($backgroundProcess) { Write-DesktopStatus $DesktopContext 'ready' ("Campus routes ready; mode: "+$config.connectionMode) $backgroundProcess.Drain() }
                Write-Host 'READY: native campus route configuration is applied. Run Test-Connection.ps1 to verify access.'
            }
        }
        if ($backgroundProcess -and $lastReady) { Write-DesktopStatus $DesktopContext 'ready' ("Campus routes ready; mode: "+$config.connectionMode) $backgroundProcess.Drain() }
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }
    if ($backgroundProcess -and $process.HasExited) {
        $process.WaitForExit()
        Write-DesktopStatus $DesktopContext 'connecting' 'Background process finished' $backgroundProcess.Drain()
    }
    if ($process.HasExited -and $process.ExitCode -ne 0) { throw "OpenConnect exited with code $($process.ExitCode)." }
} finally {
    if ($process -and -not $process.HasExited) {
        try { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
        catch { Write-Warning 'Could not stop owned OpenConnect process; run app\Recover.ps1.' }
    }
    try { Remove-CampusState "$runtime\state.json" }
    catch { Write-Warning 'Route cleanup needs attention; run app\Recover.ps1.' }
    if ($NoClash) {
        try { Restore-DirectHostMappings (Join-Path $runtime 'direct-dns.json') }
        catch { Write-Warning '校园域名映射恢复失败，请使用 GUI 异常恢复。' }
    }
    if ($clashApplied) {
        try { & "$ProjectRoot\app\Apply-Clash.ps1" -ConfigPath $ConfigPath -ClashDirectory $ClashDirectory -MihomoPath $MihomoPath -Restore }
        catch { Write-Warning 'Clash restore needs attention. Run app\Apply-Clash.ps1 -Restore or Recover.ps1.' }
    }
    $lockHandle.Dispose()
    if ($backgroundProcess) { $backgroundProcess.Dispose() }
    $env:CAMPUS_CONFIG_PATH = $oldConfigEnv
}
