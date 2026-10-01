$ProjectRoot=Split-Path $PSScriptRoot -Parent
$manifest=@(Get-Content -LiteralPath "$ProjectRoot\config\package-files.txt" | Where-Object { $_ -and -not $_.StartsWith('#') })
if (@($manifest | Select-Object -Unique).Count -ne $manifest.Count) { throw 'Duplicate package paths.' }
foreach ($relative in $manifest) {
    if ($relative -match '(^|/)(runtime|tools|tests|vendor|downloads|dist)(/|$)|\.local\.json|(^/|:|(^|/)\.\.(/|$))') { throw "Unsafe package path: $relative" }
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative) -PathType Leaf)) { throw "Missing package dependency: $relative" }
}
foreach ($folder in @('app','scripts')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot $folder) -File) {
        if ($manifest -notcontains "$folder/$($file.Name)") { throw "Runtime dependency not packaged: $($file.Name)" }
    }
}
foreach ($file in Get-ChildItem -LiteralPath "$ProjectRoot\app" -Filter '*.ps1') {
    $text=[IO.File]::ReadAllText($file.FullName)
    foreach ($match in [regex]::Matches($text,'\$ProjectRoot\\((?:app|scripts|config)\\[A-Za-z0-9_.-]+\.(?:ps1|cs|json|js))\b')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $match.Groups[1].Value))) { throw "Broken application path in $($file.Name): $($match.Value)" }
    }
}
$sample=Get-Content -LiteralPath "$ProjectRoot\config\config.example.json" -Raw | ConvertFrom-Json
if (@($sample.targets).Count -or @($sample.routes).Count -or @($sample.hosts).Count) { throw 'Release template contains user targets.' }
Write-Host 'Repository dependency paths and package allowlist passed.'
