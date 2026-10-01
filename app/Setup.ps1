param([string]$SevenZipPath)
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
$version = '9.21'
$expectedHash = '6ee9e8eb9bc59ef70bb0717df7f99703f8a2ccd11d8e45d58a61f9a2e6ef7d00'
$url = 'https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=MinGW64%2FGnuTLS'
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Only Windows x64 is currently supported.' }
$downloads = "$ProjectRoot\downloads"
$vendor = "$ProjectRoot\vendor\openconnect"
New-Item -ItemType Directory -Path $downloads,$vendor -Force | Out-Null
$installer = Join-Path $downloads "openconnect-$version.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer
}
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw 'OpenConnect download SHA256 mismatch. Refusing to extract or execute.'
}
if (-not (Test-Path -LiteralPath "$vendor\openconnect.exe")) {
    if (-not $SevenZipPath) {
        $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
        if ($command) { $SevenZipPath = $command.Source }
        elseif (Test-Path -LiteralPath "$env:ProgramFiles\7-Zip\7z.exe") { $SevenZipPath = "$env:ProgramFiles\7-Zip\7z.exe" }
    }
    if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath)) {
        throw 'Install 7-Zip, or pass -SevenZipPath <7z.exe>. The installer is extracted without a system-wide install.'
    }
    & $SevenZipPath x $installer "-o$vendor" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7-Zip extraction failed.' }
}
$savedPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$protocols = & "$vendor\openconnect.exe" --version 2>&1 | Out-String
$versionExit = $LASTEXITCODE
$ErrorActionPreference = $savedPreference
if ($versionExit -ne 0) { throw 'OpenConnect version check failed.' }
if ($protocols -notmatch 'Supported protocols:.*array') { throw 'Array support is missing.' }
if (-not (Test-Path -LiteralPath "$vendor\wintun.dll")) { throw 'Wintun is missing.' }
Write-Host "OpenConnect $version + Array + Wintun ready (portable)."
if (-not (Test-Path -LiteralPath "$ProjectRoot\config.local.json")) {
    Copy-Item -LiteralPath "$ProjectRoot\config\config.example.json" -Destination "$ProjectRoot\config.local.json"
}
