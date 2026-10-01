. "$PSScriptRoot\..\scripts\Common.ps1"
. "$PSScriptRoot\..\scripts\DesktopConfig.ps1"
if (-not ('CampusCredentialServer' -as [type])) { Add-Type -Path "$PSScriptRoot\..\scripts\DesktopBridge.cs" }
$passed=0
$mixed=Split-CampusTargets "192.0.2.10`nNODE.CAMPUS.EXAMPLE`nnode.campus.example."
if ($mixed.IPs.Count -ne 1 -or $mixed.Domains.Count -ne 1 -or $mixed.Domains[0] -ne 'node.campus.example' -or $mixed.Targets.Count -ne 2) { throw 'Mixed target normalization failed.' }; $passed++
foreach ($bad in @('https://node.campus.example','bad..tongji.cn','*.tongji.cn','node.campus.example:22','-bad.tongji.cn')) {
    $rejected=$false
    try { Split-CampusTargets $bad | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Malformed domain accepted.' }; $passed++
}
$fixtureRoot=Join-Path $PSScriptRoot '..\runtime\tests'
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$fixtureConfig=Get-Content -LiteralPath "$PSScriptRoot\..\config\config.example.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$fixtureConfig.targets=@('192.0.2.10','node.campus.example')
$fixturePath=Join-Path $fixtureRoot 'mixed-targets.json'
Save-CampusState $fixtureConfig $fixturePath
$normalized=Read-CampusConfig $fixturePath
if ($normalized.routes[0] -ne '192.0.2.10/32' -or $normalized.hosts[0] -ne 'node.campus.example' -or $normalized.hosts.Count -ne 1) { throw 'targets did not override legacy fields.' }; $passed++
$fixtureConfig.PSObject.Properties.Remove('targets')
$fixtureConfig.hosts=@('node.campus.example')
Save-CampusState $fixtureConfig $fixturePath
$legacy=Read-CampusConfig $fixturePath
if ($legacy.hosts[0] -ne 'node.campus.example') { throw 'Legacy host configuration was not retained.' }; $passed++
$ips=@(ConvertFrom-CampusHostList "192.0.2.10`n192.0.2.11,192.0.2.10")
if ($ips.Count -ne 2 -or $ips[0] -ne '192.0.2.10') { throw 'Host list deduplication failed.' }
$passed++
if (@(ConvertFrom-CampusHostList '').Count -ne 0) { throw 'Empty host list refused.' }; $passed++
foreach ($bad in @('10.0.0.0/8','localhost','198.18.0.1','127.0.0.1','0.0.0.0','10.1.1.999','010.1.1.1')) {
    $rejected=$false
    try { ConvertFrom-CampusHostList $bad | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Invalid host address accepted.' }; $passed++
}
foreach ($badPassword in @('',"abc`nxyz")) {
    $rejected=$false
    try { [CampusCredentialServer]::Validate('test-user',$badPassword) } catch { $rejected=$true }
    if (-not $rejected) { throw 'Unsafe credential accepted.' }; $passed++
}
$secret='synthetic-test-password'
if ([CampusBackgroundProcess]::Redact("echo $secret",$secret).Contains($secret)) { throw 'Password leaked in redacted line.' }; $passed++
if ([CampusBackgroundProcess]::Redact('Set-Cookie: fixture','x').Contains('fixture')) { throw 'Cookie leaked.' }; $passed++
$pipeName='tongji-auth-'+[Guid]::NewGuid().ToString('N')
$server=[CampusCredentialServer]::new($pipeName)
try {
    $receive=[CampusCredentialClient]::ReceiveAsync($pipeName,$PID)
    $deadline=(Get-Date).AddSeconds(10)
    while (-not $server.Connected -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 30 }
    if (-not $server.Connected) { throw 'Synthetic local pipe failed to connect.' }
    $rejected=$false
    try { $server.Send(($PID+1),'test-user',$secret) } catch { $rejected=$true }
    if (-not $rejected) { throw 'Wrong pipe client PID accepted.' }; $passed++
    $server.Send($PID,'test-user',$secret)
    if (-not $receive.Wait(10000)) { throw 'Synthetic credential handoff did not finish.' }
    if ($receive.Result[0] -ne 'test-user' -or $receive.Result[1] -ne $secret) { throw 'Credential pipe payload mismatch.' }
    $passed++
} finally { $server.Dispose(); $secret=$null }
$fixtureCode='$value=[Console]::ReadLine(); [Console]::WriteLine("echo:"+$value); [Console]::Error.WriteLine("Set-Cookie: fixture"); exit 0'
$fixtureArgs='-NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fixtureCode))
$syntheticPassword='synthetic-stdin-secret'
$runner=[CampusBackgroundProcess]::new("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",$fixtureArgs,$syntheticPassword)
try {
    if (-not $runner.Process.WaitForExit(10000)) { $runner.Process.Kill(); throw 'Synthetic background child did not exit.' }
    $runner.Process.WaitForExit()
    $captured=$runner.Drain() -join "`n"
    if ($runner.Process.ExitCode -ne 0) { throw "PowerShell fixture exited with code $($runner.Process.ExitCode)." }
    if ($captured.Contains($syntheticPassword)) { throw 'Background output exposed synthetic stdin secret.' }
    if ($captured.Contains('Set-Cookie')) { throw 'Background output exposed cookie header.' }
    if (-not $captured.Contains('echo:[hidden]')) {
        $safe=($captured -split "`n" | ForEach-Object { [CampusBackgroundProcess]::Redact($_,$syntheticPassword) }) -join '; '
        throw "PowerShell fixture did not echo stdin; sanitized output: $safe"
    }
    $passed++
} finally { $runner.Dispose(); $syntheticPassword=$null }
$fixtureBinary=Join-Path $fixtureRoot ('background-fixture-'+[Guid]::NewGuid().ToString('N')+'.exe')
Add-Type -Path "$PSScriptRoot\fixtures\BackgroundFixture.cs" -OutputAssembly $fixtureBinary -OutputType ConsoleApplication
foreach ($iteration in 1..8) {
    $syntheticPassword='synthetic-native-stdin-'+[char]0x79d8+[char]0x5bc6
    $previousEncoding=[Console]::InputEncoding
    $runner=$null
    try {
        [Console]::InputEncoding=[Text.UTF8Encoding]::new(($iteration % 2) -eq 1)
        $preambleLength=[Console]::InputEncoding.GetPreamble().Length
        $runner=[CampusBackgroundProcess]::new($fixtureBinary,'',$syntheticPassword)
        if ([Console]::InputEncoding.GetPreamble().Length -ne $preambleLength) { throw 'Background startup changed host input encoding.' }
        if (-not $runner.Process.WaitForExit(10000)) { $runner.Process.Kill(); throw 'Native fixture timed out.' }
        $runner.Process.WaitForExit()
        $captured=$runner.Drain() -join "`n"
        if ($runner.Process.ExitCode -ne 0) { throw "Native fixture exited with code $($runner.Process.ExitCode)." }
        if ($captured.Contains($syntheticPassword) -or $captured.Contains('Set-Cookie')) { throw 'Native fixture output was not redacted.' }
        foreach ($expected in @('echo:[hidden]','stdout-tail','stderr-tail')) {
            if (-not $captured.Contains($expected)) { throw "Native fixture missing $expected on iteration $iteration." }
        }
        $passed++
    } finally { if ($runner) { $runner.Dispose() }; [Console]::InputEncoding=$previousEncoding; $syntheticPassword=$null }
}
$previousEncoding=[Console]::InputEncoding
try {
    [Console]::InputEncoding=[Text.UTF8Encoding]::new($true)
    $rejected=$false
    try { [CampusBackgroundProcess]::new((Join-Path $fixtureRoot ('missing-'+[Guid]::NewGuid().ToString('N')+'.exe')),'','synthetic-secret') | Out-Null } catch { $rejected=$true }
    if (-not $rejected -or [Console]::InputEncoding.GetPreamble().Length -ne 3) { throw 'Failed child startup did not restore host encoding.' }
    $passed++
} finally { [Console]::InputEncoding=$previousEncoding }
Write-Host "$passed desktop checks passed. Only synthetic credentials were used; no campus login attempted."
