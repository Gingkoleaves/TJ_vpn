. "$PSScriptRoot\..\scripts\Common.ps1"
. "$PSScriptRoot\..\scripts\DesktopConfig.ps1"
if (-not ('CampusCredentialServer' -as [type])) { Add-Type -Path "$PSScriptRoot\..\scripts\DesktopBridge.cs" }
$passed=0
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
$fixtureArgs='-NoProfile -Command '+(ConvertTo-NativeArgument $fixtureCode)
$syntheticPassword='synthetic-stdin-secret'
$runner=[CampusBackgroundProcess]::new("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",$fixtureArgs,$syntheticPassword)
try {
    if (-not $runner.Process.WaitForExit(10000)) { $runner.Process.Kill(); throw 'Synthetic background child did not exit.' }
    $runner.Process.WaitForExit()
    $captured=$runner.Drain() -join "`n"
    if ($runner.Process.ExitCode -ne 0 -or $captured.Contains($syntheticPassword) -or $captured.Contains('Set-Cookie') -or -not $captured.Contains('echo:[hidden]')) { throw 'Background stdin/output isolation failed.' }
    $passed++
} finally { $runner.Dispose(); $syntheticPassword=$null }
Write-Host "$passed desktop checks passed. Only synthetic credentials were used; no campus login attempted."
