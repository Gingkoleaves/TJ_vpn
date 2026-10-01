param([Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path $PSScriptRoot -Parent
$PackagePath=(Resolve-Path -LiteralPath $PackagePath).Path
$checksum=[IO.File]::ReadAllText($PackagePath+'.sha256').Trim()
$hash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($checksum -ne ($hash+'  '+[IO.Path]::GetFileName($PackagePath))) { throw 'Package SHA256 mismatch.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($PackagePath)
$packageName=[IO.Path]::GetFileNameWithoutExtension($PackagePath)
$extractRoot=Join-Path $ProjectRoot ('runtime\tests\portable package '+[Guid]::NewGuid().ToString('N'))
$expected=@(Get-Content -LiteralPath "$ProjectRoot\config\package-files.txt" | Where-Object { $_ -and -not $_.StartsWith('#') })
$expected+=@('TongjiVPN.exe','bin/campus-config.exe')
foreach ($file in Get-ChildItem -LiteralPath "$ProjectRoot\third-party-licenses" -Recurse -File) { $expected+=$file.FullName.Substring($ProjectRoot.Length+1).Replace('\','/') }
try {
    $files=@($archive.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName.Replace('\','/') })
    if (@($files | Select-Object -Unique).Count -ne $files.Count) { throw 'Duplicate ZIP entries.' }
    foreach ($name in $files) {
        if (-not $name.StartsWith($packageName+'/') -or $name -match '(^/|:|(^|/)\.\.(/|$))') { throw "Unsafe ZIP path: $name" }
        $relative=$name.Substring($packageName.Length+1)
        if ($expected -notcontains $relative) { throw "Unexpected package file: $relative" }
    }
    foreach ($relative in $expected) { if ($files -notcontains ($packageName+'/'+$relative)) { throw "Missing package file: $relative" } }
} finally { $archive.Dispose() }
[IO.Compression.ZipFile]::ExtractToDirectory($PackagePath,$extractRoot)
$root=Join-Path $extractRoot $packageName
foreach ($folder in @('app','scripts')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $folder) -Filter '*.ps1') {
        $tokens=$null; $errors=$null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        if ($errors) { throw "Packaged script parse failed: $($file.Name)" }
    }
}
$stdout=Join-Path $extractRoot 'launcher.stdout.log'; $stderr=Join-Path $extractRoot 'launcher.stderr.log'
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=Join-Path $root 'TongjiVPN.exe'; $info.Arguments='--smoke-test'; $info.WorkingDirectory=$extractRoot
$info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
$process=[Diagnostics.Process]::Start($info)
try {
    $outputTask=$process.StandardOutput.ReadToEndAsync(); $errorTask=$process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Packaged launcher timed out.' }
    [IO.File]::WriteAllText($stdout,$outputTask.Result); [IO.File]::WriteAllText($stderr,$errorTask.Result)
    if ($process.ExitCode -ne 0) { throw ('Packaged launcher failed: '+$errorTask.Result) }
    if ($outputTask.Result -notmatch 'GUI construction smoke test passed') { throw 'Packaged GUI did not report success.' }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'runtime\tests\gui-config.json'))) { throw 'GUI resolved runtime outside package root.' }
    if (Test-Path -LiteralPath (Join-Path $extractRoot 'runtime')) { throw 'GUI used working directory for runtime.' }
} finally { $process.Dispose() }
Write-Host 'Package SHA256, exact contents, script syntax and extracted launcher passed. No network changed.'
