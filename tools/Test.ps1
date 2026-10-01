param([switch]$SkipRust)
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
$failures = @()
Get-ChildItem -Path "$ProjectRoot\app\*.ps1","$ProjectRoot\tools\*.ps1","$ProjectRoot\scripts\*.ps1","$ProjectRoot\tests\*.ps1" | ForEach-Object {
    $parseTokens=$null; $parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$parseTokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors) { $failures += "$($_.Name): $($parseErrors.Message -join ', ')" }
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Host 'PowerShell syntax passed.'
& "$ProjectRoot\tests\Test-Layout.ps1"
& "$ProjectRoot\tests\Test-Safety.ps1"
& "$ProjectRoot\tests\Test-Http.ps1"
& "$ProjectRoot\tests\Test-Desktop.ps1"
& "$ProjectRoot\tests\Test-DesktopStatus.ps1"
& "$ProjectRoot\tests\Test-CampusDns.ps1"
& "$ProjectRoot\tests\Test-TargetResolution.ps1"
& "$ProjectRoot\tests\Test-ConnectionMode.ps1"
if ($env:OS -eq 'Windows_NT') {
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "$ProjectRoot\app\Gui.ps1" -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw 'GUI construction failed.' }
}
if (-not $SkipRust) {
    Push-Location $ProjectRoot
    try {
        cargo fmt --check
        if ($LASTEXITCODE -ne 0) { throw 'Rust formatting check failed.' }
        cargo test --locked
        if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed.' }
        cargo clippy --locked --all-targets -- -D warnings
        if ($LASTEXITCODE -ne 0) { throw 'Rust clippy failed.' }
    } finally { Pop-Location }
}
