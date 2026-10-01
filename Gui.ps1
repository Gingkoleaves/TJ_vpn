param([switch]$SmokeTest, [string]$PreviewPath)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\scripts\Common.ps1"
. "$PSScriptRoot\scripts\DesktopConfig.ps1"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path "$PSScriptRoot\scripts\DesktopBridge.cs"
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
# The panel itself does not need elevation. Only the existing connection and
# recovery entry points request administrator rights when a network change is needed.
$mutex = [Threading.Mutex]::new($false, 'Local\TongjiOpenConnectDesktopV3')
$ownsMutex = $SmokeTest -or $mutex.WaitOne(0)
if (-not $ownsMutex) {
    $existingWindow=[CampusWindow]::FindWindow($null,'同济校园 VPN · 0.3.0 预发布')
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
$script:authSession = $null
$script:backgroundSession = ''
$script:backgroundStamp = ''
$script:lastStatus = ''
$runtime = Join-Path $PSScriptRoot 'runtime'
$form = [Windows.Forms.Form]::new()
$form.Text = '同济校园 VPN · 0.3.0 预发布'
$form.Size = [Drawing.Size]::new(800,730)
$form.MinimumSize = [Drawing.Size]::new(800,730)
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
$userLabel = Add-Label '校园账号' 26 213 85 30
$script:userBox=[Windows.Forms.TextBox]::new()
$script:userBox.Location=[Drawing.Point]::new(112,210); $script:userBox.Size=[Drawing.Size]::new(190,30)
$script:userBox.MaxLength=128; $form.Controls.Add($script:userBox)
$passwordLabel = Add-Label '密码' 324 213 60 30
$script:passwordBox=[Windows.Forms.TextBox]::new()
$script:passwordBox.Location=[Drawing.Point]::new(382,210); $script:passwordBox.Size=[Drawing.Size]::new(248,30)
$script:passwordBox.UseSystemPasswordChar=$true; $script:passwordBox.MaxLength=4096; $form.Controls.Add($script:passwordBox)
$note = Add-Label '输入账号密码，点击连接并允许管理员权限。密码不会保存；Clash 保持运行。' 26 252 730 48

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
    if ($File -eq 'Recover.ps1') {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Recover.ps1"')
        Add-Log '已打开管理员恢复终端；请查看该终端结果。'
        return
    }
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
$connect=Add-Button '连接' 26 332 170 {
    Invoke-Safely {
        if ($script:connected -or $script:liveProcess -or $script:authSession) { Add-Log '已有校园连接或认证操作。'; return }
        if ($script:task) { Add-Log '请等待当前操作完成。'; return }
        if ($script:connectionWindow -and -not $script:connectionWindow.HasExited) { Add-Log '后台连接正在运行，请稍候。'; return }
        [CampusCredentialServer]::Validate($script:userBox.Text,$script:passwordBox.Text)
        $pipeName='tongji-auth-'+[Guid]::NewGuid().ToString('N')
        $server=[CampusCredentialServer]::new($pipeName)
        try {
            $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSScriptRoot+'\Background.ps1" -PipeName '+$pipeName+' -GuiProcessId '+$PID
            $script:connectionWindow=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
            $script:authSession=[pscustomobject]@{server=$server;worker=$script:connectionWindow;deadline=(Get-Date).AddSeconds(60)}
            $script:backgroundSession=$pipeName; $script:backgroundStamp=''
            Add-Log '后台连接已启动，正在通过本机专用管道传递认证信息。'
        } catch { $server.Dispose(); $script:passwordBox.Clear(); throw }
    }
}
$disconnect=Add-Button '断开' 212 332 170 {
    Invoke-Safely {
        if ($script:authSession) {
            $script:authSession.server.Dispose(); $script:authSession=$null; $script:passwordBox.Clear()
        }
        if (-not $script:liveProcess -and -not ($script:connectionWindow -and -not $script:connectionWindow.HasExited)) { Add-Log '当前没有校园连接。'; return }
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        if ($script:backgroundSession) { [IO.File]::WriteAllText((Join-Path $runtime 'disconnect-background.request'),$script:backgroundSession,[Text.UTF8Encoding]::new($false)) }
        [IO.File]::WriteAllText((Join-Path $runtime 'disconnect.request'),'disconnect',[Text.UTF8Encoding]::new($false))
        Add-Log '已请求连接程序退出并恢复分流。若终端无响应，使用异常恢复。'
    }
}
$edit=Add-Button '配置' 398 332 170 {
    Invoke-Safely {
        $path=Join-Path $PSScriptRoot 'config.local.json'
        if ((Show-CampusHostEditor $form $path) -eq 'OK') { Add-Log '校园主机 IP 已保存，下次连接生效。' }
    }
}
$logs=Add-Button '日志' 584 332 170 { Invoke-Safely { $script:logBox.Focus(); $script:logBox.SelectionStart=$script:logBox.TextLength; $script:logBox.ScrollToCaret() } }
$script:logBox=[Windows.Forms.RichTextBox]::new()
$script:logBox.Location=[Drawing.Point]::new(26,395); $script:logBox.Size=[Drawing.Size]::new(730,240)
$script:logBox.ReadOnly=$true; $script:logBox.BackColor=[Drawing.Color]::White
$script:logBox.Anchor='Top,Bottom,Left,Right'; $form.Controls.Add($script:logBox)
$footer=Add-Label '密码不保存；关闭面板后已建立的 VPN 继续运行。退出校园网请点击“断开连接”。' 26 648 730 32
$footer.Anchor='Bottom,Left,Right'
function Update-Panel {
    $script:connected=$false; $script:liveProcess=$false
    $state=$null
    try {
        if ($script:authSession) {
            try {
                if ($script:authSession.server.Connected) {
                    $script:authSession.server.Send($script:authSession.worker.Id,$script:userBox.Text,$script:passwordBox.Text)
                    $script:passwordBox.Clear(); $script:authSession.server.Dispose(); $script:authSession=$null
                    Add-Log '认证信息已交给后台进程；面板密码输入已清空。'
                } elseif ((Get-Date) -gt $script:authSession.deadline -or $script:authSession.worker.HasExited) {
                    throw 'Background credential handoff timed out or worker exited.'
                }
            } catch {
                if ($script:authSession) { $script:authSession.server.Dispose(); $script:authSession=$null }
                $script:passwordBox.Clear(); Add-Log $_.Exception.Message
            }
        }
        $pidPath=Join-Path $runtime 'process.json'
        if (Test-Path -LiteralPath $pidPath) {
            $owner=Get-Content -LiteralPath $pidPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $process=Get-Process -Id $owner.id -ErrorAction SilentlyContinue
            $expectedBinary=Join-Path $PSScriptRoot 'vendor\openconnect\openconnect.exe'
            $script:liveProcess=[bool]($process -and $process.ProcessName -eq 'openconnect' -and $owner.path -eq $expectedBinary -and
                (-not $process.Path -or $process.Path -eq $owner.path) -and $process.StartTime.ToUniversalTime().ToString('o') -eq $owner.startedAt)
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
            $script:detailLabel.Text='校园连接已建立。可访问配置中的校园主机；外网继续使用 Clash。'
        } elseif ($script:liveProcess) {
            $script:statusLabel.Text='连接中 / 等待本机认证'
            $script:statusLabel.ForeColor=[Drawing.Color]::FromArgb(150,100,20)
            $script:detailLabel.Text='后台正在连接校园网，请稍候。'
        } else {
            $script:statusLabel.Text='校园 VPN 未连接'
            $script:statusLabel.ForeColor=[Drawing.Color]::FromArgb(70,80,100)
            $script:detailLabel.Text='填写账号密码后点击连接。首次使用需要下载客户端并安装 7-Zip。'
        }
        if ($script:lastStatus -ne $script:statusLabel.Text) { Add-Log $script:statusLabel.Text; $script:lastStatus=$script:statusLabel.Text }
        $backgroundPath=Join-Path $runtime 'background.json'
        if ($script:backgroundSession -and (Test-Path -LiteralPath $backgroundPath)) {
            $background=Get-Content -LiteralPath $backgroundPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($background.session -eq $script:backgroundSession) {
                if ($background.updatedAt -ne $script:backgroundStamp) {
                    if ($background.phase -eq 'error') { Add-Log ('连接失败：'+$background.message) }
                    $script:backgroundStamp=$background.updatedAt
                    $script:logBox.Text=(@($background.logs) -join "`r`n")+"`r`n"+$background.message
                }
                if ($background.phase -eq 'error') { $script:statusLabel.Text='连接失败'; $script:detailLabel.Text=$background.message }
                elseif ($background.phase -in @('auth','setup','connecting')) { $script:statusLabel.Text='后台连接中…'; $script:detailLabel.Text=$background.message }
            }
        }
        $busyWorker=$script:connectionWindow -and -not $script:connectionWindow.HasExited
        $connect.Enabled=(-not $script:liveProcess -and -not $script:task -and -not $script:authSession -and -not $busyWorker)
        $script:userBox.Enabled=(-not $script:authSession)
        $script:passwordBox.Enabled=(-not $script:authSession)
        $disconnect.Enabled=($script:liveProcess -or $busyWorker)
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
    Add-Log '密码通过限制本机当前用户访问的管道传递，不写入文件或命令行。'
    if ($SmokeTest) {
        $script:statusLabel.Text='预览：校园 VPN 未连接'
        $script:detailLabel.Text='界面构建测试；未读取校园状态，未启动进程或改变网络配置。'
        if ($PreviewPath) {
            $form.Show(); $form.Refresh(); [Windows.Forms.Application]::DoEvents()
            $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try { $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save($PreviewPath) }
            finally { $bitmap.Dispose(); $form.Hide() }
        }
        $buttonTexts=@($form.Controls | Where-Object { $_ -is [Windows.Forms.Button] } | ForEach-Object Text)
        if (($buttonTexts -join ',') -ne '连接,断开,配置,日志') { throw 'Panel must contain exactly the four requested buttons.' }
        if (-not $script:passwordBox.UseSystemPasswordChar) { throw 'Password field is not masked.' }
        $configFixture=Join-Path $PSScriptRoot 'runtime\tests\gui-config.json'
        New-Item -ItemType Directory -Path (Split-Path $configFixture -Parent) -Force | Out-Null
        Copy-Item -LiteralPath "$PSScriptRoot\config.example.json" -Destination $configFixture
        $editorResult=Show-CampusHostEditor $form $configFixture -SmokeTest
        $edited=Read-CampusConfig $configFixture
        if ($editorResult -ne 'OK' -or $edited.routes.Count -ne 2 -or $edited.routes[1] -ne '192.0.2.11/32') { throw 'Host configuration dialog save failed.' }
        Write-Host 'GUI construction smoke test passed. No network action performed.'
    } else {
        $timer.Start()
        # The elevated PowerShell host uses SW_HIDE for its console. Explicitly
        # show the panel after its first ShowWindow consumes that startup flag.
        $form.Show()
        [CampusWindow]::ShowWindow($form.Handle,9) | Out-Null
        [CampusWindow]::SetForegroundWindow($form.Handle) | Out-Null
        [Windows.Forms.Application]::Run($form)
    }
} finally {
    $timer.Stop(); $timer.Dispose(); $form.Dispose()
    if ($script:authSession) { $script:authSession.server.Dispose() }
    if (-not $SmokeTest -and $ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
