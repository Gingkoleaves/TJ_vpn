param([string]$Version = '0.3.0-preview.7')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') { throw 'Invalid package version.' }
$helper = "$PSScriptRoot\bin\campus-config.exe"
if (-not (Test-Path -LiteralPath $helper)) { throw 'Run Build.ps1 first.' }
$launcher = "$PSScriptRoot\bin\TongjiVPN.exe"
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run Build.ps1: GUI launcher is missing.' }
$dist = "$PSScriptRoot\dist"
$stage = Join-Path $dist "tongji-openconnect-$Version-windows-x64"
if (Test-Path -LiteralPath $stage) { throw 'Package staging path already exists. Use another version or remove your previous package.' }
New-Item -ItemType Directory -Path $stage,(Join-Path $stage 'bin') -Force | Out-Null
# Explicit allowlist: never package runtime, private profiles, config.local.json,
# downloaded VPN binaries, passwords or the surrounding workspace.
$files = @('Connect.ps1','Start.ps1','Start.cmd','StartGUI.cmd','Gui.ps1','Setup.ps1','Status.ps1','Doctor.ps1',
    'Recover.ps1','Update-CampusRoutes.ps1','Apply-Clash.ps1','Test-Connection.ps1',
    'Background.ps1','Test-Hpc.ps1','config.example.json','README.md','LICENSE','THIRD-PARTY.md')
foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stage $file) }
Copy-Item -LiteralPath "$PSScriptRoot\scripts" -Destination "$stage\scripts" -Recurse
Copy-Item -LiteralPath $helper -Destination "$stage\bin\campus-config.exe"
Copy-Item -LiteralPath $launcher -Destination "$stage\TongjiVPN.exe"
Copy-Item -LiteralPath "$PSScriptRoot\third-party-licenses" -Destination "$stage\third-party-licenses" -Recurse
New-Item -ItemType Directory -Path "$stage\docs" -Force | Out-Null
foreach ($document in @('VALIDATION.md','RELEASE.md')) {
    Copy-Item -LiteralPath "$PSScriptRoot\docs\$document" -Destination "$stage\docs\$document"
}
$zip = "$stage.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$hash  $([IO.Path]::GetFileName($zip))`n", [Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $zip -Algorithm SHA256 | Format-List
Write-Host "Portable package: $zip"
