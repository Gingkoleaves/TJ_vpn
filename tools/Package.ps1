param([string]$Version = '0.3.0-preview.8')
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') { throw 'Invalid package version.' }
$helper = "$ProjectRoot\bin\campus-config.exe"
if (-not (Test-Path -LiteralPath $helper)) { throw 'Run tools\Build.ps1 first.' }
$launcher = "$ProjectRoot\bin\TongjiVPN.exe"
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run tools\Build.ps1: GUI launcher is missing.' }
$dist = "$ProjectRoot\dist"
$stage = Join-Path $dist "tongji-openconnect-$Version-windows-x64"
if (Test-Path -LiteralPath $stage) { throw 'Package staging path already exists. Use another version or remove your previous package.' }
New-Item -ItemType Directory -Path $stage,(Join-Path $stage 'bin') -Force | Out-Null
# Explicit allowlist: never package runtime, private profiles, config.local.json,
# downloaded VPN binaries, passwords or the surrounding workspace.
$files=@(Get-Content -LiteralPath "$ProjectRoot\config\package-files.txt" | Where-Object { $_ -and -not $_.StartsWith('#') })
foreach ($file in $files) {
    if ($file -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))') { throw "Invalid package manifest path: $file" }
    $destination=Join-Path $stage $file
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $file) -Destination $destination
}
Copy-Item -LiteralPath $helper -Destination "$stage\bin\campus-config.exe"
Copy-Item -LiteralPath $launcher -Destination "$stage\TongjiVPN.exe"
Copy-Item -LiteralPath "$ProjectRoot\third-party-licenses" -Destination "$stage\third-party-licenses" -Recurse
$zip = "$stage.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$hash  $([IO.Path]::GetFileName($zip))`n", [Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $zip -Algorithm SHA256 | Format-List
Write-Host "Portable package: $zip"
