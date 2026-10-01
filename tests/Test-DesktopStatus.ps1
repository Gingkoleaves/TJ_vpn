. "$PSScriptRoot\..\scripts\Common.ps1"
. "$PSScriptRoot\..\scripts\DesktopStatus.ps1"
$testDirectory=Join-Path $PSScriptRoot '..\runtime\tests'
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
$context=New-DesktopStatusContext (Join-Path $testDirectory 'desktop-status.json') 'synthetic-session'
$childPath=Join-Path $testDirectory 'desktop-status-child.ps1'
$childSource=@'
param($Context, [string]$Root)
. "$Root\scripts\Common.ps1"
. "$Root\scripts\DesktopStatus.ps1"
Write-DesktopStatus $Context 'ready' 'Cross-script status update' @('test log')
if ($Context.State.session -ne 'synthetic-session') { throw 'Session context was lost.' }
'@
[IO.File]::WriteAllText($childPath,$childSource,[Text.UTF8Encoding]::new($true))
& $childPath -Context $context -Root (Split-Path $PSScriptRoot -Parent)
$stored=Get-Content -LiteralPath $context.Path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($stored.phase -ne 'ready' -or $context.State.phase -ne 'ready' -or $stored.logs[0] -ne 'test log') { throw 'Cross-script context update failed.' }
Write-DesktopStatus $context 'connecting' 'Retention check' @(1..100 | ForEach-Object {"line $_"})
if ($context.State.logs.Count -ne 80 -or $context.State.logs[-1] -ne 'line 100') { throw 'Status log retention failed.' }
Write-Host '2 desktop status regression checks passed across script scopes. No VPN started.'
