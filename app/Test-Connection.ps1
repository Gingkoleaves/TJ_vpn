param([int]$Count = 1, [int]$IntervalSeconds = 10, [string]$ConfigPath = "$PSScriptRoot\..\config.local.json")
$ProjectRoot = Split-Path $PSScriptRoot -Parent
. "$ProjectRoot\scripts\Common.ps1"
if ($Count -lt 1 -or $Count -gt 10000 -or $IntervalSeconds -lt 0) { throw 'Invalid sampling options.' }
$config = Read-CampusConfig $ConfigPath
$sessionPath=Join-Path $ProjectRoot 'runtime\session-config.json'
if (Test-Path -LiteralPath $sessionPath) { $config=Read-CampusConfig $sessionPath }
$direct=$config.PSObject.Properties['connectionMode'] -and $config.connectionMode -eq 'direct'
New-Item -ItemType Directory -Path "$ProjectRoot\runtime" -Force | Out-Null
$statePath = "$ProjectRoot\runtime\state.json"
$results = @()
for ($sample = 1; $sample -le $Count; $sample++) {
    $campusReady = $false
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $adapter = Get-NetAdapter -InterfaceIndex $state.interfaceIndex -ErrorAction SilentlyContinue
        $campusReady = $state.connected -and (Test-CampusAdapter $adapter $state.interfaceName) -and $adapter.Status -eq 'Up'
    }
    foreach ($test in @(@{name='campus';url='https://software.tongji.edu.cn'}, @{name='external';url='https://www.google.com'})) {
        $errorFile = "$ProjectRoot\runtime\curl-error.txt"
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $proxyArgs=if($direct){@('--noproxy','*')}else{@('--proxy',"http://127.0.0.1:$($config.clashProxyPort)")}
            $result = & curl.exe -sS @proxyArgs --connect-timeout 5 --max-time 15 -o NUL -w '%{http_code},%{time_total}' $test.url 2>$errorFile
            $curlExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $savedPreference }
        $parts = ([string]$result).Split(',')
        $record = [pscustomobject]@{time=(Get-Date).ToString('o'); sample=$sample; target=$test.name;
            httpCode=$parts[0]; seconds=if($parts.Count -gt 1){$parts[1]}else{''}; curlExit=$curlExit; campusReady=[bool]$campusReady}
        $results += $record
        Write-Host "$($test.name): HTTP $($record.httpCode), $($record.seconds)s, campusReady=$campusReady"
    }
    if ($sample -lt $Count) { Start-Sleep -Seconds $IntervalSeconds }
}
$results | Export-Csv -LiteralPath "$ProjectRoot\runtime\checks.csv" -NoTypeInformation -Encoding UTF8
if (@($results | Where-Object { $_.curlExit -ne 0 -or $_.httpCode -ne '200' -or ($_.target -eq 'campus' -and -not $_.campusReady) }).Count) { exit 1 }
