. "$PSScriptRoot\..\scripts\Common.ps1"
. "$PSScriptRoot\..\scripts\TargetResolution.ps1"
$passed=0
foreach ($response in @([pscustomobject]@{Status=3},[pscustomobject]@{Status=0},[pscustomobject]@{Status=0;Answer=@([pscustomobject]@{type=1;data='198.18.0.1'})})) {
    $rejected=$false
    try { ConvertFrom-PublicDnsResponse $response | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Invalid public response accepted.' }; $passed++
}
$valid=[pscustomobject]@{Status=0;Answer=@([pscustomobject]@{type=5;data='canonical.example'},[pscustomobject]@{type=1;data='192.0.2.10'})}
if (@(ConvertFrom-PublicDnsResponse $valid)[0] -ne '192.0.2.10') { throw 'Public A record extraction failed.' }; $passed++
$script:campusWorks=$true; $script:publicWorks=$false; $script:publicCalls=0
function Get-CampusDnsAnswers { param($HostName,$Server,$Source) if ($script:campusWorks) { return '192.0.2.10' }; throw 'Synthetic campus DNS failure' }
function Get-PublicDnsAnswers { param($HostName,$ProxyPort) $script:publicCalls++; if ($script:publicWorks) { return '192.0.2.11' }; throw 'Synthetic NXDOMAIN' }
$state=[pscustomobject]@{dns=@('202.120.190.208');address='192.0.2.100'}
$config=[pscustomobject]@{clashProxyPort=7897}
$result=Resolve-CampusTarget 'test.tongji.edu.cn' $state $config
if ($result.dnsSource -ne 'campus' -or $script:publicCalls -ne 0) {throw 'Campus-first order failed'}; $passed++
$script:campusWorks=$false; $script:publicWorks=$true
$result=Resolve-CampusTarget 'test.tongji.edu.cn' $state $config
if ($result.dnsSource -ne 'public' -or $result.addresses[0] -ne '192.0.2.11') {throw 'Public fallback failed'}; $passed++
$script:publicWorks=$false
$result=Resolve-CampusTarget 'test.tongji.edu.cn' $state $config
if ($result.dnsSource -ne 'unresolved' -or $result.addresses.Count -ne 0 -or $result.error -notmatch 'NXDOMAIN') {throw 'Failed domain should be a diagnostic result rather than terminate VPN'}; $passed++
Write-Host "$passed resolution fallback checks passed using mocks. No VPN changed."
function Get-ReferenceCampusAnswers { param($HostName) if ($HostName -eq 'node.campus.example') { return @('192.0.2.10','192.0.2.11') }; return @() }
$result=Resolve-CampusTarget 'node.campus.example' $state $config
if ($result.dnsSource -ne 'reference-pdf' -or $result.addresses.Count -ne 2) { throw 'Local reference fallback failed' }
function Test-CampusSshNode { param($Address,$Source) return $Address -eq '192.0.2.11' }
Select-CampusReachableNodes $result $state.address
if ($result.addresses.Count -ne 1 -or $result.addresses[0] -ne '192.0.2.11') { throw 'Reachable pool selection failed' }
function Test-CampusSshNode { param($Address,$Source) return $false }
Select-CampusReachableNodes $result $state.address
if ($result.addresses.Count -ne 1) { throw 'Transient failure must retain pool for retries' }
$script:campusWorks=$true
$result=Resolve-CampusTarget 'node.campus.example' $state $config
if ($result.dnsSource -ne 'campus') { throw 'Local reference must not override live DNS' }
Write-Host '4 local-reference and node-selection checks passed using documentation-only addresses.'
$script:campusWorks=$false; $script:publicWorks=$true; $script:lastPort=-1
function Get-PublicDnsAnswers { param($HostName,$ProxyPort) $script:lastPort=$ProxyPort; return '192.0.2.11' }
$config | Add-Member -NotePropertyName connectionMode -NotePropertyValue 'direct' -Force
$result=Resolve-CampusTarget 'node.campus.example' $state $config
if ($script:lastPort -ne 0 -or $result.dnsSource -ne 'public') { throw 'Direct DNS still depends on Clash.' }
$config.connectionMode='clash'
$result=Resolve-CampusTarget 'node.campus.example' $state $config
if ($script:lastPort -ne 7897) { throw 'Proxy DNS lost configured port.' }
Write-Host '2 mode-specific DNS checks passed.'
