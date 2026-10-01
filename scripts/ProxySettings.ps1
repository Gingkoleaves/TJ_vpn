function Show-ProxySettings($Owner,$Settings,[string]$Path,[switch]$SmokeTest) {
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text='代理设置（Clash Verge 联动）'
    $dialog.Size=[Drawing.Size]::new(640,360); $dialog.StartPosition='CenterParent'; $dialog.Font=$Owner.Font
    $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $boxes=@{}; $row=20
    foreach ($field in @(@('mihomoPath','mihomo 内核'),@('clashDirectory','配置目录'),@('clashPipe','控制管道'),@('clashProxyPort','代理端口'))) {
        $label=[Windows.Forms.Label]::new(); $label.Text=$field[1]; $label.SetBounds(16,$row,110,28); $dialog.Controls.Add($label)
        $box=[Windows.Forms.TextBox]::new(); $box.Text=[string]$Settings.($field[0]); $box.SetBounds(130,$row,370,28); $dialog.Controls.Add($box); $boxes[$field[0]]=$box
        $row+=42
    }
    $browse=[Windows.Forms.Button]::new(); $browse.Text='选择文件'; $browse.SetBounds(510,20,100,30); $dialog.Controls.Add($browse)
    $browse.Add_Click({ $picker=[Windows.Forms.OpenFileDialog]::new(); $picker.Filter='可执行文件 (*.exe)|*.exe'; try { if ($picker.ShowDialog($dialog) -eq 'OK') { $boxes.mihomoPath.Text=$picker.FileName } } finally { $picker.Dispose() } })
    $folder=[Windows.Forms.Button]::new(); $folder.Text='选择目录'; $folder.SetBounds(510,62,100,30); $dialog.Controls.Add($folder)
    $folder.Add_Click({ $picker=[Windows.Forms.FolderBrowserDialog]::new(); try { if ($picker.ShowDialog($dialog) -eq 'OK') { $boxes.clashDirectory.Text=$picker.SelectedPath } } finally { $picker.Dispose() } })
    $result=[Windows.Forms.Label]::new(); $result.SetBounds(16,192,590,62); $result.Text='内核路径留空时自动查找。检测与保存不会修改或关闭现有代理。'; $dialog.Controls.Add($result)
    $detect=[Windows.Forms.Button]::new(); $detect.Text='自动查找内核'; $detect.SetBounds(16,264,140,34); $dialog.Controls.Add($detect)
    $detect.Add_Click({ try { $boxes.mihomoPath.Text=Find-Mihomo ''; $result.Text='已找到：'+$boxes.mihomoPath.Text } catch { $result.Text=$_.Exception.Message } })
    $save=[Windows.Forms.Button]::new(); $save.Text='保存'; $save.SetBounds(400,264,100,34); $dialog.Controls.Add($save)
    $cancel=[Windows.Forms.Button]::new(); $cancel.Text='取消'; $cancel.SetBounds(510,264,100,34); $cancel.DialogResult='Cancel'; $dialog.Controls.Add($cancel)
    $save.Add_Click({
        try {
            $candidate=[pscustomobject]@{mode=$Settings.mode;mihomoPath=$boxes.mihomoPath.Text.Trim();clashDirectory=$boxes.clashDirectory.Text.Trim();clashPipe=$boxes.clashPipe.Text.Trim();clashProxyPort=[int]$boxes.clashProxyPort.Text}
            if ($candidate.clashPipe -notmatch '^[A-Za-z0-9_-]+$' -or $candidate.clashProxyPort -lt 1 -or $candidate.clashProxyPort -gt 65535) { throw '管道名或端口无效。' }
            if ($candidate.mihomoPath) { Assert-MihomoBinary (Find-Mihomo $candidate.mihomoPath) }
            Save-CampusState $candidate $Path
            $dialog.DialogResult='OK'; $dialog.Close()
        } catch { $result.Text=$_.Exception.Message }
    })
    if ($SmokeTest) { $dialog.Add_Shown({ $save.PerformClick(); if ($dialog.Visible) { $dialog.Close() } }) }
    try { return $dialog.ShowDialog($Owner) } finally { $dialog.Dispose() }
}
