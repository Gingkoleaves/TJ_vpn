param([string]$ConfigPath = "$PSScriptRoot\config.local.json", [string]$UserName)
. "$PSScriptRoot\scripts\Common.ps1"
Assert-Administrator
if (-not (Test-Path -LiteralPath $ConfigPath)) { Copy-Item -LiteralPath "$PSScriptRoot\config.example.json" -Destination $ConfigPath }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Read-CampusConfig $ConfigPath
$binary = "$PSScriptRoot\vendor\openconnect\openconnect.exe"
if (-not (Test-Path -LiteralPath $binary)) { throw 'Run Setup.ps1 first.' }
$version = & $binary --version 2>&1 | Out-String
if ($version -notmatch 'Supported protocols:.*array') { throw 'This OpenConnect build does not support Array.' }
$runtime = "$PSScriptRoot\runtime"
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$lockPath = Join-Path $runtime 'connection.lock'
$lockHandle = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$oldConfigEnv = $env:CAMPUS_CONFIG_PATH
$env:CAMPUS_CONFIG_PATH = $ConfigPath
$hook = "$PSScriptRoot\scripts\vpnc-hook.js"
$arguments = @('--protocol=array', '--no-dtls', '--disable-ipv6', '--interface', $config.interfaceName, '--script', $hook)
if ($UserName) { $arguments += @('--user', $UserName) }
$arguments += $config.server
Write-Host 'Keep Clash running. Leave authgroup EMPTY; enter your campus username/password locally.'
Write-Host 'Keep this terminal open. Press Ctrl+C to disconnect. No password or cookie is saved.'
try {
    & $binary @arguments
    if ($LASTEXITCODE -ne 0) { throw "OpenConnect exited with code $LASTEXITCODE." }
} finally {
    Remove-CampusState "$runtime\state.json"
    $lockHandle.Dispose()
    $env:CAMPUS_CONFIG_PATH = $oldConfigEnv
}
