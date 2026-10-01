$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
$previousRustFlags=$env:RUSTFLAGS
# Rust panic/source locations must not expose the builder's profile or workspace.
$env:RUSTFLAGS=($previousRustFlags + ' --remap-path-prefix="' + $env:USERPROFILE + '=C:\build-user" --remap-path-prefix="' + $ProjectRoot + '=C:\build\tongji-openconnect"').Trim()
Push-Location $ProjectRoot
try {
    cargo build --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed.' }
    # Prebuilt Rust std embeds source paths that remap-path-prefix cannot rewrite.
    # Replace only the builder's profile prefix, preserving each PE byte offset.
    $byteEncoding=[Text.Encoding]::GetEncoding(28591)
    foreach ($binaryName in @('campus-config.exe','tongji-vpn-launcher.exe')) {
        $binaryPath=Join-Path "$ProjectRoot\target\release" $binaryName
        $data=$byteEncoding.GetString([IO.File]::ReadAllBytes($binaryPath))
        foreach ($pathEncoding in @([Text.Encoding]::UTF8,[Text.Encoding]::Unicode)) {
            $privateBytes=$pathEncoding.GetBytes($env:USERPROFILE)
            $publicPath='C:\build'.PadRight($env:USERPROFILE.Length,'_')
            $publicBytes=$pathEncoding.GetBytes($publicPath)
            if ($publicBytes.Length -lt $privateBytes.Length) {
                $padding=[byte[]]::new($privateBytes.Length-$publicBytes.Length)
                for ($i=0;$i -lt $padding.Length;$i++) { $padding[$i]=95 }
                $publicBytes=[byte[]](@($publicBytes)+@($padding))
            }
            if ($privateBytes.Length -ne $publicBytes.Length) { throw 'Cannot sanitize diagnostic path without changing binary size.' }
            $data=$data.Replace($byteEncoding.GetString($privateBytes),$byteEncoding.GetString($publicBytes))
        }
        [IO.File]::WriteAllBytes($binaryPath,$byteEncoding.GetBytes($data))
    }
    New-Item -ItemType Directory -Path "$ProjectRoot\bin" -Force | Out-Null
    Copy-Item -LiteralPath "$ProjectRoot\target\release\campus-config.exe" -Destination "$ProjectRoot\bin\campus-config.exe"
    Copy-Item -LiteralPath "$ProjectRoot\target\release\tongji-vpn-launcher.exe" -Destination "$ProjectRoot\bin\TongjiVPN.exe"
    Copy-Item -LiteralPath "$ProjectRoot\bin\TongjiVPN.exe" -Destination "$ProjectRoot\TongjiVPN.exe"
    Write-Host 'Rust configuration helper built.'
} finally { Pop-Location; $env:RUSTFLAGS=$previousRustFlags }
