param([string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') { throw 'Invalid package version.' }
$helper = "$PSScriptRoot\bin\campus-config.exe"
if (-not (Test-Path -LiteralPath $helper)) { throw 'Run Build.ps1 first.' }
$dist = "$PSScriptRoot\dist"
$stage = Join-Path $dist "tongji-openconnect-$Version-windows-x64"
if (Test-Path -LiteralPath $stage) { throw 'Package staging path already exists. Use another version or remove your previous package.' }
New-Item -ItemType Directory -Path $stage,(Join-Path $stage 'bin') -Force | Out-Null
# Explicit allowlist: never package runtime, private profiles, config.local.json,
# downloaded VPN binaries, passwords or the surrounding workspace.
$files = @('Connect.ps1','Start.ps1','Start.cmd','Setup.ps1','Status.ps1','Doctor.ps1',
    'Recover.ps1','Update-CampusRoutes.ps1','Apply-Clash.ps1','Test-Connection.ps1',
    'config.example.json','README.md','LICENSE','THIRD-PARTY.md')
foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stage $file) }
Copy-Item -LiteralPath "$PSScriptRoot\scripts" -Destination "$stage\scripts" -Recurse
Copy-Item -LiteralPath $helper -Destination "$stage\bin\campus-config.exe"
$zip = "$stage.zip"
Compress-Archive -LiteralPath $stage -DestinationPath $zip
Get-FileHash -LiteralPath $zip -Algorithm SHA256 | Format-List
Write-Host "Portable package: $zip"
