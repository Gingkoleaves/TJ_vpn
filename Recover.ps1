param([string]$ConfigPath = "$PSScriptRoot\config.local.json", [string]$MihomoPath)
. "$PSScriptRoot\scripts\Common.ps1"
Assert-Administrator
$pidPath = "$PSScriptRoot\runtime\process.json"
if (Test-Path -LiteralPath $pidPath) {
    $owned = Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $process = Get-Process -Id $owned.id -ErrorAction SilentlyContinue
    if ($process -and $process.Path -eq $owned.path -and $process.StartTime.ToUniversalTime().ToString('o') -eq $owned.startedAt) {
        Stop-Process -Id $process.Id -Force
    }
}
Remove-CampusState "$PSScriptRoot\runtime\state.json"
& "$PSScriptRoot\Apply-Clash.ps1" -ConfigPath $ConfigPath -MihomoPath $MihomoPath -Restore
Write-Host 'Recovery completed; only recorded campus changes were removed.'
