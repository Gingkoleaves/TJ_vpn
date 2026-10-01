function ConvertFrom-CampusHostList([string]$Text) {
    $addresses=@()
    foreach ($entry in @($Text -split '[\s,;，；]+' | Where-Object { $_ })) {
        $ip=$null
        if ($entry -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or -not [Net.IPAddress]::TryParse($entry,[ref]$ip) -or $ip.ToString() -ne $entry) {
            throw "Invalid campus IPv4 address: $entry"
        }
        Assert-CampusPrefix "$entry/32"
        $addresses += $entry
    }
    return @($addresses | Select-Object -Unique)
}

function Show-CampusHostEditor($Owner, [string]$ConfigPath, [switch]$SmokeTest) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Copy-Item -LiteralPath "$PSScriptRoot\..\config\config.example.json" -Destination $ConfigPath
    }
    $config=Read-CampusConfig $ConfigPath
    $dialog=[Windows.Forms.Form]::new()
    $dialog.Text='校园访问目标'; $dialog.Size=[Drawing.Size]::new(460,420)
    $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'
    $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false; $dialog.Font=$Owner.Font
    $label=[Windows.Forms.Label]::new()
    $label.Text='每行一个 IP 或域名，例如 node.campus.example。保存后重新连接生效。'
    $label.Location=[Drawing.Point]::new(20,18); $label.Size=[Drawing.Size]::new(410,45)
    $dialog.Controls.Add($label)
    $hostListBox=[Windows.Forms.TextBox]::new()
    $hostListBox.Multiline=$true; $hostListBox.ScrollBars='Vertical'; $hostListBox.AcceptsReturn=$true
    $hostListBox.Location=[Drawing.Point]::new(20,68); $hostListBox.Size=[Drawing.Size]::new(400,205)
    $hostListBox.Text=(@(@($config.routes | ForEach-Object { ($_ -split '/')[0] }) + @($config.hosts) | Select-Object -Unique) -join "`r`n")
    $dialog.Controls.Add($hostListBox)
    $errorLabel=[Windows.Forms.Label]::new()
    $errorLabel.ForeColor=[Drawing.Color]::Firebrick
    $errorLabel.Location=[Drawing.Point]::new(20,280); $errorLabel.Size=[Drawing.Size]::new(400,40)
    $dialog.Controls.Add($errorLabel)
    $save=[Windows.Forms.Button]::new(); $save.Text='保存'; $save.Location=[Drawing.Point]::new(230,328); $save.Size=[Drawing.Size]::new(90,32)
    $cancel=[Windows.Forms.Button]::new(); $cancel.Text='取消'; $cancel.Location=[Drawing.Point]::new(330,328); $cancel.Size=[Drawing.Size]::new(90,32)
    $cancel.DialogResult='Cancel'; $dialog.CancelButton=$cancel
    $save.Add_Click({
        try {
            $parsed=Split-CampusTargets ($hostListBox.Text -replace '[，；]',',')
            if ($parsed.Domains -contains ([Uri]$config.server).Host) { throw 'VPN gateway cannot be configured as a campus target.' }
            $config.routes=@($parsed.IPs | ForEach-Object { "$_/32" })
            $config.hosts=@($parsed.Domains)
            $config | Add-Member -NotePropertyName targets -NotePropertyValue @($parsed.Targets) -Force
            Save-CampusState $config $ConfigPath
            $dialog.DialogResult='OK'; $dialog.Close()
        } catch { $errorLabel.Text=$_.Exception.Message }
    })
    $dialog.Controls.Add($save); $dialog.Controls.Add($cancel)
    if ($SmokeTest) {
        $dialog.Add_Shown({ $hostListBox.Text="192.0.2.10`r`n192.0.2.11`r`nnode.campus.example"; $save.PerformClick(); if ($dialog.Visible) { $dialog.Close() } })
    }
    try { return $dialog.ShowDialog($Owner) } finally { $dialog.Dispose() }
}
