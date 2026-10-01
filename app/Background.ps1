param([Parameter(Mandatory=$true)][string]$PipeName, [Parameter(Mandatory=$true)][int]$GuiProcessId)
$ProjectRoot = Split-Path $PSScriptRoot -Parent
. "$ProjectRoot\scripts\Common.ps1"
. "$ProjectRoot\scripts\DesktopStatus.ps1"
. "$ProjectRoot\scripts\ConnectionMode.ps1"
if ($PipeName -notmatch '^tongji-auth-[a-f0-9]{32}$') { throw 'Invalid authentication pipe.' }
$runtime=Join-Path $ProjectRoot 'runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$statusPath=Join-Path $runtime 'background.json'
$desktopContext=New-DesktopStatusContext $statusPath $PipeName
$credential=$null
try {
    Assert-Administrator
    $settings=Read-ConnectionSettings (Join-Path $ProjectRoot 'connection.local.json')
    $resolved=Resolve-ConnectionMode $settings
    Add-Type -Path "$ProjectRoot\scripts\DesktopBridge.cs"
    Write-DesktopStatus $desktopContext 'auth' 'Waiting for GUI credential handoff'
    $values=[CampusCredentialClient]::Receive($PipeName,$GuiProcessId)
    $secure=ConvertTo-SecureString $values[1] -AsPlainText -Force
    $credential=[pscredential]::new($values[0],$secure)
    $values=$null
    Write-DesktopStatus $desktopContext 'setup' 'Preparing verified OpenConnect'
    if (-not (Test-Path -LiteralPath "$ProjectRoot\vendor\openconnect\openconnect.exe")) { & "$ProjectRoot\app\Setup.ps1" }
    $stopPath=Join-Path $runtime 'disconnect-background.request'
    if ((Test-Path -LiteralPath $stopPath) -and (Get-Content -LiteralPath $stopPath -Raw) -eq $PipeName) {
        Write-DesktopStatus $desktopContext 'disconnected' 'Connection canceled before authentication'
        return
    }
    Write-DesktopStatus $desktopContext 'connecting' 'Authenticating and creating campus tunnel'
    & "$ProjectRoot\app\Connect.ps1" -Credential $credential -DesktopContext $desktopContext -NoClash:($resolved.mode -eq 'direct') -MihomoPath $resolved.mihomoPath -ClashDirectory $settings.clashDirectory -ClashPipe $settings.clashPipe -ClashProxyPort $settings.clashProxyPort
    Write-DesktopStatus $desktopContext 'disconnected' 'Campus connection stopped; cleanup completed'
} catch {
    Write-DesktopStatus $desktopContext 'error' $_.Exception.Message
    exit 1
} finally {
    if ($credential) { $credential.Password.Dispose() }
    $credential=$null
}
