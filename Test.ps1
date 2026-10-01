param([switch]$SkipRust)
$ErrorActionPreference = 'Stop'
$failures = @()
Get-ChildItem -Path "$PSScriptRoot\*.ps1","$PSScriptRoot\scripts\*.ps1","$PSScriptRoot\tests\*.ps1" | ForEach-Object {
    $parseTokens=$null; $parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$parseTokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors) { $failures += "$($_.Name): $($parseErrors.Message -join ', ')" }
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Host 'PowerShell syntax passed.'
& "$PSScriptRoot\tests\Test-Safety.ps1"
& "$PSScriptRoot\tests\Test-Http.ps1"
& "$PSScriptRoot\tests\Test-Desktop.ps1"
& "$PSScriptRoot\tests\Test-DesktopStatus.ps1"
& "$PSScriptRoot\tests\Test-CampusDns.ps1"
& "$PSScriptRoot\tests\Test-TargetResolution.ps1"
& "$PSScriptRoot\tests\Test-ConnectionMode.ps1"
if ($env:OS -eq 'Windows_NT') {
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "$PSScriptRoot\Gui.ps1" -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw 'GUI construction failed.' }
}
if (-not $SkipRust) {
    Push-Location $PSScriptRoot
    try {
        cargo fmt --check
        if ($LASTEXITCODE -ne 0) { throw 'Rust formatting check failed.' }
        cargo test --locked
        if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed.' }
        cargo clippy --locked --all-targets -- -D warnings
        if ($LASTEXITCODE -ne 0) { throw 'Rust clippy failed.' }
    } finally { Pop-Location }
}
