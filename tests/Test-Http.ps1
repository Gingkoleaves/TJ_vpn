. "$PSScriptRoot\..\scripts\Clash.ps1"
$utf8 = [Text.Encoding]::UTF8
$body = '{"name":"' + [char]0x65e5 + [char]0x672c + '"}'
$payload = $utf8.GetBytes($body)
$chunkHeader = "HTTP/1.1 200 OK`r`nTransfer-Encoding: chunked`r`n`r`n" + $payload.Length.ToString('x') + "`r`n"
$wire = $utf8.GetBytes($chunkHeader + $body + "`r`n0`r`n`r`n")
$decoded = ConvertFrom-ClashResponse $wire
if ($decoded.name -ne ([string][char]0x65e5 + [char]0x672c)) { throw 'UTF8 chunk decoding failed.' }
$plain = "HTTP/1.1 200 OK`r`nContent-Length: $($payload.Length)`r`n`r`n$body"
if ((ConvertFrom-ClashResponse $utf8.GetBytes($plain)).name -ne $decoded.name) { throw 'Content-Length decoding failed.' }
$empty = "HTTP/1.1 204 No Content`r`n`r`n"
if ($null -ne (ConvertFrom-ClashResponse $utf8.GetBytes($empty))) { throw 'Empty 204 failed.' }
foreach ($bad in @("HTTP/1.1 200 OK`r`nContent-Length: 99`r`n`r`n{}", "HTTP/1.1 400 Bad Request`r`n`r`n{}", $chunkHeader + '{}')) {
    $rejected = $false
    try { ConvertFrom-ClashResponse $utf8.GetBytes($bad) | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Corrupt/error HTTP response accepted.' }
}
Write-Host '6 HTTP checks passed, including non-ASCII proxy names.'
