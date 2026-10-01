if (-not ('CampusDns' -as [type])) { Add-Type -Path "$PSScriptRoot\..\scripts\CampusDns.cs" }
function Name-Bytes([string]$Name) {
    $bytes=@()
    foreach ($label in $Name.Split('.')) { $bytes += [byte]$label.Length; $bytes += [Text.Encoding]::ASCII.GetBytes($label) }
    $bytes += [byte]0
    return [byte[]]$bytes
}
$hostName='node.campus.example'
$question=[byte[]](@(Name-Bytes $hostName)+@(0,1,0,1))
$record=[byte[]]@(192,12,0,1,0,1,0,0,0,60,0,4,192,0,2,10)
$response=[byte[]](@(18,52,129,128,0,1,0,1,0,0,0,0)+@($question)+@($record))
$answers=[CampusDns]::Parse($response,0x1234,$hostName)
if ($answers.Count -ne 1 -or $answers[0] -ne '192.0.2.10') { throw 'Compressed A response failed.' }
$passed=1
foreach ($case in @('wrong-id','wrong-question','truncated','nxdomain')) {
    $fixture=$response.Clone(); $id=0x1234; $questionHost=$hostName
    switch ($case) {
        'wrong-id' { $id=0x9999 }
        'wrong-question' { $questionHost='other.tongji.edu.cn' }
        'truncated' { $fixture=[byte[]]$fixture[0..($fixture.Length-2)] }
        'nxdomain' { $fixture[3]=131 }
    }
    $rejected=$false
    try { [CampusDns]::Parse($fixture,$id,$questionHost) | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw "Invalid DNS response accepted: $case" }; $passed++
}
$alias=Name-Bytes 'node.tongji.edu.cn'
$cname=[byte[]](@(192,12,0,5,0,1,0,0,0,60,0,$alias.Length)+@($alias))
$aliasA=[byte[]](@($alias)+@(0,1,0,1,0,0,0,60,0,4,192,0,2,11))
$cnameResponse=[byte[]](@(18,52,129,128,0,1,0,2,0,0,0,0)+@($question)+@($cname)+@($aliasA))
if ([CampusDns]::Parse($cnameResponse,0x1234,$hostName)[0] -ne '192.0.2.11') { throw 'CNAME chain did not resolve.' }; $passed++
Write-Host "$passed campus DNS parser checks passed using synthetic packets; no live VPN query."
