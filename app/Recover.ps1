param([string]$ConfigPath = "$PSScriptRoot\..\config.local.json", [string]$MihomoPath, [string]$GuiResultPath)
$ProjectRoot = Split-Path $PSScriptRoot -Parent
. "$ProjectRoot\scripts\Common.ps1"
. "$ProjectRoot\scripts\DirectDns.ps1"
. "$ProjectRoot\scripts\ConnectionMode.ps1"
try {
Assert-Administrator
New-Item -ItemType Directory -Path "$ProjectRoot\runtime" -Force | Out-Null
$pidPath = "$ProjectRoot\runtime\process.json"
if (Test-Path -LiteralPath $pidPath) {
    $owned = Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $process = Get-Process -Id $owned.id -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -eq 'openconnect' -and $owned.path -eq "$ProjectRoot\vendor\openconnect\openconnect.exe" -and $process.Path -eq $owned.path -and $process.StartTime.ToUniversalTime().ToString('o') -eq $owned.startedAt) {
        Stop-Process -Id $process.Id -Force
    }
}
$deadline=(Get-Date).AddSeconds(8)
$lock=$null
while (-not $lock) {
    try { $lock=[IO.File]::Open("$ProjectRoot\runtime\connection.lock",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { if ((Get-Date) -gt $deadline) { throw '后台连接尚未完成清理，请稍后重试异常恢复。' }; Start-Sleep -Milliseconds 100 }
}
try {
Remove-CampusState "$ProjectRoot\runtime\state.json"
Restore-DirectHostMappings "$ProjectRoot\runtime\direct-dns.json"
$settings=Read-ConnectionSettings (Join-Path $ProjectRoot 'connection.local.json')
if (-not $MihomoPath) { $MihomoPath=$settings.mihomoPath }
$sessionPath=Join-Path $ProjectRoot 'runtime\session-config.json'
if (Test-Path -LiteralPath $sessionPath) { $ConfigPath=$sessionPath }
& "$ProjectRoot\app\Apply-Clash.ps1" -ConfigPath $ConfigPath -MihomoPath $MihomoPath -ClashDirectory $settings.clashDirectory -Restore
} finally { $lock.Dispose() }
Write-Host 'Recovery completed; only recorded campus changes were removed.'
if ($GuiResultPath) { Save-CampusState ([pscustomobject]@{message='恢复完成；仅清理校园连接与映射，Clash 保持运行。'}) $GuiResultPath }
} catch {
    if ($GuiResultPath) { Save-CampusState ([pscustomobject]@{message=$_.Exception.Message}) $GuiResultPath }
    Write-Error $_
    exit 1
}
