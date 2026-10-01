. "$PSScriptRoot\..\scripts\ConnectionMode.ps1"
. "$PSScriptRoot\..\scripts\DirectDns.ps1"
$root=Join-Path $PSScriptRoot '..\runtime\tests\connection-mode'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$settings=Read-ConnectionSettings (Join-Path $root 'missing.json')
$script:present=$false
function Get-ProxyPresence { param($PipeName,$Port) return $script:present }
function Assert-ClashHealth { param($PipeName,$Port) if ($script:badHealth) { throw 'Synthetic controller failure' } }
function Find-Mihomo { param($ExplicitPath) if ($ExplicitPath -eq 'missing') { throw 'Synthetic missing kernel' }; return 'synthetic.exe' }
function Assert-MihomoBinary { param($Path) }
$script:badHealth=$false
if ((Resolve-ConnectionMode $settings).mode -ne 'direct') { throw 'Absent proxy must select direct.' }
$settings.mode='direct'
if ((Resolve-ConnectionMode $settings).mode -ne 'direct') { throw 'Explicit direct failed.' }
$script:present=$true
$rejected=$false; try { Resolve-ConnectionMode $settings | Out-Null } catch { $rejected=$true }
if (-not $rejected) { throw 'Running proxy silently bypassed.' }
$settings.mode='auto'; $settings.clashDirectory=$root
New-Item -ItemType Directory -Path (Join-Path $root 'profiles') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'clash-verge.yaml'),'fixture')
[IO.File]::WriteAllText((Join-Path $root 'profiles\Script.js'),'fixture')
if ((Resolve-ConnectionMode $settings).mode -ne 'clash') { throw 'Running healthy proxy must select clash.' }
$script:badHealth=$true
$rejected=$false; try { Resolve-ConnectionMode $settings | Out-Null } catch { $rejected=$true }
if (-not $rejected) { throw 'Broken controller silently downgraded.' }
$script:badHealth=$false; $settings.mihomoPath='missing'
$rejected=$false; try { Resolve-ConnectionMode $settings | Out-Null } catch { $rejected=$true }
if (-not $rejected) { throw 'Missing binary silently downgraded.' }
$hosts=Join-Path $root 'hosts.fixture'; $journal=Join-Path $root 'dns.json'
[IO.File]::WriteAllText($hosts,"127.0.0.1 localhost`r`n# original comment`r`n")
$domain=[pscustomobject]@{hostName='node.campus.example';addresses=@('192.0.2.10')}
Set-DirectHostMappings @($domain) $journal $hosts
if ([IO.File]::ReadAllText($hosts) -notmatch '192.0.2.10 node.campus.example # TongjiVPN-') { throw 'Mapping missing.' }
[IO.File]::AppendAllText($hosts,"192.0.2.20 other.example # user change`r`n")
Restore-DirectHostMappings $journal $hosts
$restored=[IO.File]::ReadAllText($hosts)
if ($restored -match 'TongjiVPN-' -or $restored -notmatch 'user change' -or $restored -notmatch 'original comment') { throw 'Ownership restoration lost user edits.' }
Restore-DirectHostMappings $journal $hosts
[IO.File]::AppendAllText($hosts,"192.0.2.30 node.campus.example`r`n")
$before=[IO.File]::ReadAllText($hosts)
$rejected=$false; try { Set-DirectHostMappings @($domain) $journal $hosts } catch { $rejected=$true }
if (-not $rejected -or [IO.File]::ReadAllText($hosts) -ne $before) { throw 'Existing hosts mapping overwritten.' }
Write-Host '10 mode and DNS ownership checks passed. No system hosts, proxy or VPN changed.'
