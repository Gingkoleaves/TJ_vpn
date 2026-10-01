param([switch]$SmokeTest, [string]$PreviewPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\scripts\Common.ps1"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CampusWindow {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string title);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
'@
if (-not $SmokeTest) {
    try { Assert-Administrator }
    catch {
        Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"')
        return
    }
}
$mutex = [Threading.Mutex]::new($false, 'Local\TongjiOpenConnectDesktop')
$ownsMutex = $SmokeTest -or $mutex.WaitOne(0)
if (-not $ownsMutex) {
    $existingWindow=[CampusWindow]::FindWindow($null,'同济校园 VPN · 0.2.0 预发布')
    if ($existingWindow -ne [IntPtr]::Zero) {
        [CampusWindow]::ShowWindow($existingWindow,9) | Out-Null
        [CampusWindow]::SetForegroundWindow($existingWindow) | Out-Null
    } else {
        [Windows.Forms.MessageBox]::Show('管理窗口正在启动，请稍候再试。', '同济校园 VPN') | Out-Null
    }
    $mutex.Dispose()
    return
}
$script:task = $null
$script:connectionWindow = $null
$script:lastStatus = ''
$runtime = Join-Path $PSScriptRoot 'runtime'
$form = [Windows.Forms.Form]::new()
$form.Text = '同济校园 VPN · 0.2.0 预发布'
$form.Size = [Drawing.Size]::new(800,660)
$form.MinimumSize = [Drawing.Size]::new(800,660)
$form.StartPosition = 'CenterScreen'
$form.Font = [Drawing.Font]::new('Microsoft YaHei UI',10)
$form.BackColor = [Drawing.Color]::FromArgb(245,247,251)

function Add-Label([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    $label = [Windows.Forms.Label]::new()
    $label.Text=$Text; $label.Location=[Drawing.Point]::new($X,$Y); $label.Size=[Drawing.Size]::new($Width,$Height)
    $form.Controls.Add($label)
    return $label
}
$title = Add-Label '同济校园 VPN' 24 20 600 40
$title.Font = [Drawing.Font]::new('Microsoft YaHei UI',20,[Drawing.FontStyle]::Bold)
$subtitle = Add-Label 'Windows 原生连接 · 校园分流 · Clash 保持运行' 26 68 730 28
$script:statusLabel = Add-Label '正在读取连接状态…' 26 114 730 32
$script:statusLabel.Font=[Drawing.Font]::new('Microsoft YaHei UI',13,[Drawing.FontStyle]::Bold)
$script:detailLabel = Add-Label '连接状态以网卡和进程为准，实际可达性请运行连接测试。' 26 154 730 55
$note = Add-Label '点击连接后，在弹出的本机终端输入账号密码；authgroup 留空。保持认证终端打开。' 26 210 730 48

function Add-Button([string]$Text,[int]$X,[int]$Y,[int]$Width,[scriptblock]$Action) {
    $button=[Windows.Forms.Button]::new()
    $button.Text=$Text; $button.Location=[Drawing.Point]::new($X,$Y); $button.Size=[Drawing.Size]::new($Width,38)
    $button.FlatStyle='Flat'; $button.BackColor=[Drawing.Color]::White
    $button.Add_Click($Action); $form.Controls.Add($button)
    return $button
}
function Add-Log([string]$Text) {
    $script:logBox.AppendText(('['+(Get-Date -Format 'HH:mm:ss')+'] '+$Text+"`r`n"))
    if ($script:logBox.TextLength -gt 60000) { $script:logBox.Text=$script:logBox.Text.Substring($script:logBox.TextLength-40000) }
    $script:logBox.SelectionStart=$script:logBox.TextLength; $script:logBox.ScrollToCaret()
}
function Start-PanelTask([string]$File,[string]$Label) {
    if ($script:task) { Add-Log '上一项操作尚未结束，请稍候。'; return }
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    $id=[Guid]::NewGuid().ToString('N')
    $stdout=Join-Path $runtime "gui-$id.out.log"
    $stderr=Join-Path $runtime "gui-$id.err.log"
    $argsText='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot $File)+'"'
    $process=Start-Process powershell.exe -ArgumentList $argsText -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $script:task=[pscustomobject]@{process=$process; stdout=$stdout; stderr=$stderr; label=$Label}
    Add-Log "$Label 已开始；完成后在此显示结果。"
}
function Invoke-Safely([scriptblock]$Action) {
    try { & $Action } catch { Add-Log $_.Exception.Message }
}
$connect=Add-Button '连接校园网' 26 266 140 {
    Invoke-Safely {
        if ($script:connected -or $script:liveProcess) { Add-Log '已有校园连接进程，请使用现有认证窗口。'; return }
        if ($script:task) { Add-Log '请等待当前操作完成。'; return }
        if ($script:connectionWindow -and -not $script:connectionWindow.HasExited) { Add-Log '请完成或关闭已有认证窗口。'; return }
        $script:connectionWindow=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Start.ps1"') -PassThru
        Add-Log '已打开本机认证终端；账号密码只在终端输入。'
    }
}
$disconnect=Add-Button '断开连接' 178 266 140 {
    Invoke-Safely {
        if (-not $script:liveProcess) { Add-Log '没有检测到本仓库的连接进程；如需清理残留，请使用异常恢复。'; return }
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $runtime 'disconnect.request'),'disconnect',[Text.UTF8Encoding]::new($false))
        Add-Log '已请求连接程序退出并恢复分流。若终端无响应，使用异常恢复。'
    }
}
$test=Add-Button '连接测试' 330 266 140 { Invoke-Safely { Start-PanelTask 'Test-Connection.ps1' '校园 / 外网测试' } }
$doctor=Add-Button '环境检查' 482 266 140 { Invoke-Safely { Start-PanelTask 'Doctor.ps1' '环境检查' } }
$recover=Add-Button '异常恢复' 634 266 120 {
    Invoke-Safely {
        if ($script:task) { Add-Log '请等待当前操作完成。'; return }
        $answer=[Windows.Forms.MessageBox]::Show('恢复会结束本仓库的校园 VPN 并清理记录的分流。Clash 将继续运行。是否继续？','异常恢复','YesNo','Question')
        if ($answer -eq 'Yes') { Start-PanelTask 'Recover.ps1' '异常恢复' }
    }
}
$setup=Add-Button '准备客户端' 26 318 140 { Invoke-Safely { Start-PanelTask 'Setup.ps1' '准备客户端（需要 7-Zip）' } }
$edit=Add-Button '校园目标配置' 178 318 140 {
    Invoke-Safely {
        $path=Join-Path $PSScriptRoot 'config.local.json'
        if (-not (Test-Path -LiteralPath $path)) { Copy-Item -LiteralPath "$PSScriptRoot\config.example.json" -Destination $path }
        Start-Process notepad.exe -ArgumentList ('"'+$path+'"')
        Add-Log '配置修改后需要断开再连接生效。'
    }
}
$readme=Add-Button '使用说明' 330 318 140 { Invoke-Safely { Start-Process notepad.exe -ArgumentList ('"'+$PSScriptRoot+'\README.md"') } }
$logs=Add-Button '打开日志目录' 482 318 140 { Invoke-Safely { New-Item -ItemType Directory -Path $runtime -Force | Out-Null; Start-Process explorer.exe -ArgumentList ('"'+$runtime+'"') } }
$script:logBox=[Windows.Forms.RichTextBox]::new()
$script:logBox.Location=[Drawing.Point]::new(26,376); $script:logBox.Size=[Drawing.Size]::new(730,190)
$script:logBox.ReadOnly=$true; $script:logBox.BackColor=[Drawing.Color]::White
$script:logBox.Anchor='Top,Bottom,Left,Right'; $form.Controls.Add($script:logBox)
$footer=Add-Label '关闭管理窗口不会断开 VPN。需要退出校园网时，请先点击“断开连接”。' 26 578 730 32
$footer.Anchor='Bottom,Left,Right'
function Update-Panel {
    $script:connected=$false; $script:liveProcess=$false
    $state=$null
    try {
        $pidPath=Join-Path $runtime 'process.json'
        if (Test-Path -LiteralPath $pidPath) {
            $owner=Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $process=Get-Process -Id $owner.id -ErrorAction SilentlyContinue
            $script:liveProcess=[bool]($process -and $process.Path -eq $owner.path -and $process.StartTime.ToUniversalTime().ToString('o') -eq $owner.startedAt)
        }
        $statePath=Join-Path $runtime 'state.json'
        if (Test-Path -LiteralPath $statePath) {
            $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($script:liveProcess -and $state.connected) {
                $adapter=Get-NetAdapter -InterfaceIndex $state.interfaceIndex -ErrorAction SilentlyContinue
                $script:connected=[bool]((Test-CampusAdapter $adapter $state.interfaceName) -and $adapter.Status -eq 'Up')
            }
        }
        if ($script:connected) {
            $script:statusLabel.Text='校园网卡已连接 · 请测试实际可达性'
            $script:statusLabel.ForeColor=[Drawing.Color]::FromArgb(20,120,70)
            $script:detailLabel.Text="网卡：$($state.interfaceName)    地址：$($state.address)`r`n校园专用路由：$(@($state.addedRoutes).Count) 条；Clash 继续使用原外网代理。"
        } elseif ($script:liveProcess) {
            $script:statusLabel.Text='连接中 / 等待本机认证'
            $script:statusLabel.ForeColor=[Drawing.Color]::FromArgb(150,100,20)
            $script:detailLabel.Text='请查看认证终端；authgroup 留空。如果报错，复制不含密码的错误信息。'
        } else {
            $script:statusLabel.Text='校园 VPN 未连接'
            $script:statusLabel.ForeColor=[Drawing.Color]::FromArgb(70,80,100)
            $script:detailLabel.Text='点击连接，在本机终端认证。首次使用会自动下载并校验客户端，需要 7-Zip。'
        }
        if ($script:lastStatus -ne $script:statusLabel.Text) { Add-Log $script:statusLabel.Text; $script:lastStatus=$script:statusLabel.Text }
        $connect.Enabled=(-not $script:liveProcess -and -not $script:task)
        $disconnect.Enabled=$script:liveProcess
        if ($script:task -and $script:task.process.HasExited) {
            $script:task.process.Refresh()
            foreach ($path in @($script:task.stdout,$script:task.stderr)) {
                if (Test-Path -LiteralPath $path) {
                    $output=Get-Content -LiteralPath $path -Raw
                    if ($output) { Add-Log $output.Trim() }
                }
            }
            Add-Log "$($script:task.label) 完成，退出码：$($script:task.process.ExitCode)"
            $script:task.process.Dispose(); $script:task=$null
        }
    } catch { $script:statusLabel.Text='状态读取失败'; Add-Log $_.Exception.Message }
}
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=2000; $timer.Add_Tick({ Update-Panel })
try {
    Add-Log '密码不进入管理面板、日志或配置。认证在独立本机终端完成。'
    if ($SmokeTest) {
        $script:statusLabel.Text='预览：校园 VPN 未连接'
        $script:detailLabel.Text='界面构建测试；未读取校园状态，未启动进程或改变网络配置。'
        if ($PreviewPath) {
            $form.Show(); $form.Refresh(); [Windows.Forms.Application]::DoEvents()
            $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try { $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save($PreviewPath) }
            finally { $bitmap.Dispose(); $form.Hide() }
        }
        if ($form.Controls.Count -lt 15) { throw 'Panel controls are missing.' }
        Write-Host 'GUI construction smoke test passed. No network action performed.'
    } else {
        Update-Panel; $timer.Start()
        # The elevated PowerShell host uses SW_HIDE for its console. Explicitly
        # show the panel after its first ShowWindow consumes that startup flag.
        $form.Show()
        [CampusWindow]::ShowWindow($form.Handle,9) | Out-Null
        [CampusWindow]::SetForegroundWindow($form.Handle) | Out-Null
        [Windows.Forms.Application]::Run($form)
    }
} finally {
    $timer.Stop(); $timer.Dispose(); $form.Dispose()
    if (-not $SmokeTest -and $ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
