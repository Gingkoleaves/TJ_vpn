param(
    [string]$ConfigPath = "$PSScriptRoot\config.local.json",
    [string]$UserName,
    [string]$ClashDirectory = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev",
    [string]$MihomoPath,
    [switch]$NoClash
)
. "$PSScriptRoot\scripts\Clash.ps1"
Assert-Administrator
if (-not (Test-Path -LiteralPath $ConfigPath)) { Copy-Item -LiteralPath "$PSScriptRoot\config.example.json" -Destination $ConfigPath }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Read-CampusConfig $ConfigPath
if (-not $NoClash) {
    Assert-ClashHealth $config.clashPipe $config.clashProxyPort
    $MihomoPath = Find-Mihomo $MihomoPath
    if (-not (Test-Path -LiteralPath "$PSScriptRoot\bin\campus-config.exe") -and
        -not (Test-Path -LiteralPath "$PSScriptRoot\target\release\campus-config.exe")) { throw 'Run Build.ps1 or use a packaged release.' }
}
$binary = "$PSScriptRoot\vendor\openconnect\openconnect.exe"
if (-not (Test-Path -LiteralPath $binary)) { throw 'Run Setup.ps1 first.' }
$savedPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$version = & $binary --version 2>&1 | Out-String
$ErrorActionPreference = $savedPreference
if ($version -notmatch 'Supported protocols:.*array') { throw 'This OpenConnect build does not support Array.' }
$runtime = "$PSScriptRoot\runtime"
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$lockPath = Join-Path $runtime 'connection.lock'
$lockHandle = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$baseInterfaceName = $config.interfaceName
# OpenConnect treats a stale registry match as a hard failure when Wintun
# cannot reopen it. Use a distinct name for each connection, without deleting
# or resetting any existing adapter/driver (Clash must remain online).
$config.interfaceName = New-CampusInterfaceName $baseInterfaceName
$ConfigPath = Join-Path $runtime 'session-config.json'
Save-CampusState $config $ConfigPath
$oldConfigEnv = $env:CAMPUS_CONFIG_PATH
$env:CAMPUS_CONFIG_PATH = $ConfigPath
$hook = "$PSScriptRoot\scripts\vpnc-hook.js"
$arguments = @('--protocol=array', '--no-dtls', '--disable-ipv6', '--interface', $config.interfaceName, '--script', $hook)
if ($UserName) { $arguments += @('--user', $UserName) }
$arguments += $config.server
Write-Host 'Keep Clash running. Leave authgroup EMPTY; enter your campus username/password locally.'
Write-Host 'Keep this terminal open. Press Ctrl+C to disconnect. No password or cookie is saved.'
Write-Host "Session adapter: $($config.interfaceName)"
$process = $null
$clashApplied = $false
$pidPath = Join-Path $runtime 'process.json'
try {
    Remove-Item -LiteralPath "$runtime\hook-error.txt" -ErrorAction SilentlyContinue
    Remove-CampusState "$runtime\state.json"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $binary
    $info.Arguments = (($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $info.WorkingDirectory = Split-Path $binary -Parent
    $info.UseShellExecute = $false
    # The child inherits this console for hidden password entry; stdin is not captured.
    $process = [Diagnostics.Process]::Start($info)
    Save-CampusState ([pscustomobject]@{id=$process.Id; path=$binary; startedAt=$process.StartTime.ToUniversalTime().ToString('o')}) $pidPath
    $lastReady = ''
    while (-not $process.HasExited) {
        if (Test-Path -LiteralPath "$runtime\hook-error.txt") {
            throw ('Campus hook failed: ' + (Get-Content -LiteralPath "$runtime\hook-error.txt" -Raw -Encoding UTF8))
        }
        $statePath = Join-Path $runtime 'state.json'
        if (Test-Path -LiteralPath $statePath) {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.error) { throw "Campus route setup failed: $($state.error)" }
            if ($state.connected -and $state.connectedAt -ne $lastReady) {
                & "$PSScriptRoot\Update-CampusRoutes.ps1" -ConfigPath $ConfigPath
                if (-not $NoClash) {
                    & "$PSScriptRoot\Apply-Clash.ps1" -ConfigPath $ConfigPath -ClashDirectory $ClashDirectory -MihomoPath $MihomoPath
                    $clashApplied = $true
                }
                $lastReady = $state.connectedAt
                Write-Host 'READY: native campus route configuration is applied. Run Test-Connection.ps1 to verify access.'
            }
        }
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }
    if ($process.ExitCode -ne 0) { throw "OpenConnect exited with code $($process.ExitCode)." }
} finally {
    if ($process -and -not $process.HasExited) {
        try { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
        catch { Write-Warning 'Could not stop owned OpenConnect process; run Recover.ps1.' }
    }
    try { Remove-CampusState "$runtime\state.json" }
    catch { Write-Warning 'Route cleanup needs attention; run Recover.ps1.' }
    if ($clashApplied) {
        try { & "$PSScriptRoot\Apply-Clash.ps1" -ConfigPath $ConfigPath -ClashDirectory $ClashDirectory -MihomoPath $MihomoPath -Restore }
        catch { Write-Warning 'Clash restore needs attention. Run Apply-Clash.ps1 -Restore or Recover.ps1.' }
    }
    $lockHandle.Dispose()
    $env:CAMPUS_CONFIG_PATH = $oldConfigEnv
}
