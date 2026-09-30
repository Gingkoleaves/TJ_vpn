param(
    [string]$ConfigPath = "$PSScriptRoot\config.local.json",
    [string]$ClashDirectory = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev",
    [string]$MihomoPath,
    [switch]$Restore
)
. "$PSScriptRoot\scripts\Clash.ps1"
$config = Read-CampusConfig $ConfigPath
$directory = (Resolve-Path -LiteralPath $ClashDirectory).Path
$runtime = "$PSScriptRoot\runtime"
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$changePath = Join-Path $runtime 'clash-change.json'
$helper = "$PSScriptRoot\bin\campus-config.exe"
if (-not (Test-Path -LiteralPath $helper)) { $helper = "$PSScriptRoot\target\release\campus-config.exe" }
Assert-ClashHealth $config.clashPipe $config.clashProxyPort

if ($Restore) {
    if (-not (Test-Path -LiteralPath $changePath)) { Write-Host 'No Clash change to restore.'; return }
    $change = Get-Content -LiteralPath $changePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $change.active) { Write-Host 'Clash already restored.'; return }
    if ((Get-FileHash -LiteralPath $change.scriptPath).Hash -ne $change.installedScriptHash) {
        throw 'Global script was edited after installation; refusing to overwrite it. Restore the backup manually.'
    }
    $kernel = Find-Mihomo $MihomoPath
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $kernel -t -d $directory -f $change.restoreRuntime 2>&1 | Out-Null
    $validationExit = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($validationExit -ne 0) { throw 'Backup runtime failed Mihomo validation.' }
    Invoke-ClashPipe $config.clashPipe PUT '/configs' @{path=$change.restoreRuntime} | Out-Null
    Restore-ClashSelections $config.clashPipe $change.selections
    Copy-Item -LiteralPath $change.baseScript -Destination $change.scriptPath
    $change.active = $false
    Save-CampusState $change $changePath
    Write-Host 'Previous Clash runtime and global script restored without exiting Clash.'
    return
}

if (-not (Test-Path -LiteralPath $helper)) { throw 'Run Build.ps1 or use the packaged release (Rust helper is missing).' }
$statePath = Join-Path $runtime 'state.json'
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $state.connected) { throw 'Native campus connection must be ready before changing Clash.' }
$adapter = Get-NetAdapter -InterfaceIndex $state.interfaceIndex
if ($adapter.Name -ne $config.interfaceName -or $adapter.Status -ne 'Up') { throw 'Campus adapter is not up.' }
$scriptPath = Join-Path $directory 'profiles\Script.js'
$source = Join-Path $directory 'clash-verge.yaml'
$candidate = Join-Path $directory 'campus-native.yaml'
$generatedScript = Join-Path $runtime 'campus-native.js'
$baseScript = Join-Path $runtime 'clash-base.js'
$restoreRuntime = Join-Path $directory 'campus-before-native.yaml'
$kernel = Find-Mihomo $MihomoPath
$change = $null
if (Test-Path -LiteralPath $changePath) { $change = Get-Content -LiteralPath $changePath -Raw -Encoding UTF8 | ConvertFrom-Json }
if ($change -and $change.active) {
    if ((Get-FileHash -LiteralPath $scriptPath).Hash -ne $change.installedScriptHash) {
        throw 'Clash script changed externally; restore/merge manually before updating.'
    }
} else {
    Copy-Item -LiteralPath $scriptPath -Destination $baseScript
    Copy-Item -LiteralPath $source -Destination $restoreRuntime
}
& $helper render $source $ConfigPath $statePath $candidate
if ($LASTEXITCODE -ne 0) { throw 'Could not render Clash configuration.' }
& $helper script $baseScript $ConfigPath $statePath $generatedScript
if ($LASTEXITCODE -ne 0) { throw 'Could not generate global enhancement script.' }
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $kernel -t -d $directory -f $candidate 2>&1 | Out-Null
$validationExit = $LASTEXITCODE
$ErrorActionPreference = $oldPreference
if ($validationExit -ne 0) { throw 'Mihomo rejected candidate. Live Clash remains unchanged.' }
$newChange = [pscustomobject]@{
    active=$false; scriptPath=$scriptPath; baseScript=$baseScript; restoreRuntime=$restoreRuntime
    installedScriptHash=(Get-FileHash -LiteralPath $generatedScript).Hash; appliedAt=(Get-Date).ToString('o')
    selections=if($change -and $change.active){$change.selections}else{Get-ClashSelections $config.clashPipe}
}
Save-CampusState $newChange $changePath
try {
    Invoke-ClashPipe $config.clashPipe PUT '/configs' @{path=$candidate} | Out-Null
    Restore-ClashSelections $config.clashPipe $newChange.selections
    Copy-Item -LiteralPath $generatedScript -Destination $scriptPath
    $newChange.active = $true
    Save-CampusState $newChange $changePath
    Assert-ClashHealth $config.clashPipe $config.clashProxyPort
    Write-Host 'Clash native campus outlet applied; TUN, external nodes and mode retained.'
} catch {
    try {
        Invoke-ClashPipe $config.clashPipe PUT '/configs' @{path=$restoreRuntime} | Out-Null
        Restore-ClashSelections $config.clashPipe $newChange.selections
        Copy-Item -LiteralPath $baseScript -Destination $scriptPath
        $newChange.active = $false
        Save-CampusState $newChange $changePath
    } catch { Write-Warning 'Automatic restore failed. Run Apply-Clash.ps1 -Restore.' }
    throw
}
