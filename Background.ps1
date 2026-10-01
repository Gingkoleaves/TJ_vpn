param([Parameter(Mandatory=$true)][string]$PipeName, [Parameter(Mandatory=$true)][int]$GuiProcessId)
. "$PSScriptRoot\scripts\Common.ps1"
if ($PipeName -notmatch '^tongji-auth-[a-f0-9]{32}$') { throw 'Invalid authentication pipe.' }
$runtime=Join-Path $PSScriptRoot 'runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$statusPath=Join-Path $runtime 'background.json'
$script:desktopStatus=[pscustomobject]@{phase='starting';message='Preparing background connection';updatedAt='';logs=@();session=$PipeName;pid=$PID}
function Write-DesktopStatus([string]$Phase,[string]$Message,[string[]]$Lines=@()) {
    $script:desktopStatus.phase=$Phase
    $script:desktopStatus.message=$Message
    $script:desktopStatus.updatedAt=(Get-Date).ToString('o')
    $script:desktopStatus.logs=@(@($script:desktopStatus.logs)+@($Lines) | Select-Object -Last 80)
    Save-CampusState $script:desktopStatus $statusPath
}
$credential=$null
try {
    Assert-Administrator
    Add-Type -Path "$PSScriptRoot\scripts\DesktopBridge.cs"
    Write-DesktopStatus 'auth' 'Waiting for GUI credential handoff'
    $values=[CampusCredentialClient]::Receive($PipeName,$GuiProcessId)
    $secure=ConvertTo-SecureString $values[1] -AsPlainText -Force
    $credential=[pscredential]::new($values[0],$secure)
    $values=$null
    Write-DesktopStatus 'setup' 'Preparing verified OpenConnect'
    if (-not (Test-Path -LiteralPath "$PSScriptRoot\vendor\openconnect\openconnect.exe")) { & "$PSScriptRoot\Setup.ps1" }
    $stopPath=Join-Path $runtime 'disconnect-background.request'
    if ((Test-Path -LiteralPath $stopPath) -and (Get-Content -LiteralPath $stopPath -Raw) -eq $PipeName) {
        Write-DesktopStatus 'disconnected' 'Connection canceled before authentication'
        return
    }
    Write-DesktopStatus 'connecting' 'Authenticating and creating campus tunnel'
    & "$PSScriptRoot\Connect.ps1" -Credential $credential
    Write-DesktopStatus 'disconnected' 'Campus connection stopped; cleanup completed'
} catch {
    Write-DesktopStatus 'error' $_.Exception.Message
    exit 1
} finally {
    if ($credential) { $credential.Password.Dispose() }
    $credential=$null
}
