function New-DesktopStatusContext([string]$Path, [string]$Session) {
    return [pscustomobject]@{
        Path=$Path
        State=[pscustomobject]@{phase='starting';message='Preparing background connection';updatedAt='';logs=@();session=$Session;pid=$PID}
    }
}

function Write-DesktopStatus($Context, [string]$Phase, [string]$Message, [string[]]$Lines=@()) {
    $state=$Context.State
    $state.phase=$Phase
    $state.message=$Message
    $state.updatedAt=(Get-Date).ToString('o')
    $state.logs=@(@($state.logs)+@($Lines) | Select-Object -Last 80)
    Save-CampusState $state $Context.Path
}
