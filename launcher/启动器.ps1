param(
    [string]$Worker = '',
    [string]$VoiceName = '',
    [string]$SourceAudio = '',
    [string]$StatusFile = ''
)

# 音色工坊：普通用户只需要双击同目录的“启动器.bat”。
# Worker 参数仅供本脚本创建隐藏后台任务使用。
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')
# 首次运行（新电脑刚 clone）时自动生成配置，用户无需先跑脚本。
$envBat = Join-Path $PSScriptRoot '..\config\_env.bat'
if (-not (Test-Path -LiteralPath $envBat)) {
    & (Join-Path $PSScriptRoot '..\scripts\apply-config.ps1') *>&1 | Out-Null
}
$script:repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$script:cfg = Get-StackConfig
$script:job = $null
$script:jobKind = ''
$script:jobVoice = ''
$script:buttons = @()
$script:statusTick = 0
$script:logDir = Join-Path $env:TEMP 'VoiceWorkshop\logs'

function Set-CacheEnvironment($cfg) {
    $env:NUMBA_CACHE_DIR = $cfg['cache']['numba']
    $env:HF_HOME = $cfg['cache']['huggingface']
    $env:HF_HUB_CACHE = $cfg['cache']['huggingface']
    $env:MODELSCOPE_CACHE = $cfg['cache']['modelscope']
    $env:GPT_SOVITS_ROOT = $cfg['paths']['gpt_sovits_root']
    $env:PYTHONIOENCODING = 'utf-8'
    foreach ($dir in @($env:NUMBA_CACHE_DIR, $env:HF_HOME, $env:MODELSCOPE_CACHE, $script:logDir)) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}

function Quote-Arg([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-TrainingPython([string[]]$Arguments) {
    $python = Join-Path $script:cfg['paths']['gpt_sovits_root'] 'runtime\python.exe'
    Push-Location $script:cfg['paths']['gpt_sovits_root']
    try {
        & $python @Arguments
        if ($LASTEXITCODE -ne 0) { throw "处理程序返回错误码 $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

function Invoke-HiddenWorker {
    Set-CacheEnvironment $script:cfg
    $root = $script:cfg['paths']['gpt_sovits_root']
    switch ($Worker) {
        'prepare' {
            $slices = Join-Path $root "output\slicer_opt\$VoiceName"
            $asr = Join-Path $root 'output\asr_opt'
            Invoke-TrainingPython @('-s', 'tools/slice_audio.py', $SourceAudio, $slices,
                '-34', '4000', '300', '10', '500', '0.9', '0.25', '0', '1')
            Invoke-TrainingPython @('-s', 'tools/asr/funasr_asr.py', '-i', $slices, '-o', $asr, '-l', 'zh')
        }
        'train' {
            $list = Join-Path $root "output\asr_opt\$VoiceName.list"
            $slices = Join-Path $root "output\slicer_opt\$VoiceName"
            Invoke-TrainingPython @((Join-Path $script:repo 'scripts\train_v2pro.py'),
                '--exp', $VoiceName, '--list', $list, '--wav', $slices, '--stage', 'all')
        }
        'switch' {
            & (Join-Path $script:repo 'scripts\switch-voice.ps1') -Exp $VoiceName
        }
        'test' {
            & (Join-Path $script:repo 'scripts\test-tts.ps1')
        }
        default { throw '未知后台任务' }
    }
}

if ($Worker) {
    try {
        Invoke-HiddenWorker
        if ($StatusFile) { [System.IO.File]::WriteAllText($StatusFile, 'success', [System.Text.Encoding]::ASCII) }
        exit 0
    } catch {
        if ($StatusFile) { [System.IO.File]::WriteAllText($StatusFile, 'failed', [System.Text.Encoding]::ASCII) }
        Write-Error $_
        exit 1
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
Set-CacheEnvironment $script:cfg

function Test-Api {
    try {
        Invoke-WebRequest -Uri $script:cfg['paths']['api_base'] -UseBasicParsing -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return ($null -ne $_.Exception.Response)
    }
}

function Update-StatusLabels {
    $alive = Test-Api
    $labelApi.Text = if ($alive) { '朗读服务：运行中' } else { '朗读服务：未运行' }
    $labelApi.ForeColor = if ($alive) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::DarkOrange }
    try {
        $script:cfg = Get-StackConfig
        $labelVoice.Text = '当前音色：' + $script:cfg['current_voice']['exp_name']
    } catch {
        $labelVoice.Text = '当前音色：读取失败'
    }
}

function Set-Busy([bool]$Busy, [string]$Message = '') {
    foreach ($button in $script:buttons) { $button.Enabled = -not $Busy }
    if ($Message) { $labelOperation.Text = $Message }
    elseif (-not $Busy) { $labelOperation.Text = '状态：就绪' }
    $form.Cursor = if ($Busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
}

function Start-HiddenTask([string]$Kind, [string]$Voice = '', [string]$Audio = '') {
    $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $stdout = Join-Path $script:logDir "$Kind-$stamp.out.log"
    $stderr = Join-Path $script:logDir "$Kind-$stamp.err.log"
    $script:jobStdout = $stdout
    $script:jobStderr = $stderr
    $script:jobStatusFile = Join-Path $script:logDir "$Kind-$stamp.status"
    $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' + (Quote-Arg $PSCommandPath) + ' -Worker ' + $Kind
    $args += ' -StatusFile ' + (Quote-Arg $script:jobStatusFile)
    if ($Voice) { $args += ' -VoiceName ' + (Quote-Arg $Voice) }
    if ($Audio) { $args += ' -SourceAudio ' + (Quote-Arg $Audio) }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args `
        -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $script:job = $process
    $script:jobKind = $Kind
    $script:jobVoice = $Voice
}

function Get-MagiProcesses {
    $portableName = [System.IO.Path]::GetFileNameWithoutExtension($script:cfg['paths']['magi_exe'])
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -eq 'MAGI' -or $_.ProcessName -eq $portableName
    })
}

function Stop-Magi {
    $processes = @(Get-MagiProcesses)
    foreach ($process in $processes) {
        if ($process.MainWindowHandle -ne 0) { $null = $process.CloseMainWindow() }
    }
    $deadline = [DateTime]::Now.AddSeconds(12)
    while ([DateTime]::Now -lt $deadline -and @(Get-MagiProcesses).Count -gt 0) {
        Start-Sleep -Milliseconds 250
    }
    foreach ($process in @(Get-MagiProcesses)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}

function Start-Magi {
    $exe = $script:cfg['paths']['magi_exe']
    if (-not (Test-Path -LiteralPath $exe)) { throw '找不到 MAGI 阅读器，请检查配置。' }
    Start-Process -FilePath $exe | Out-Null
}

function Stop-VoiceService {
    $connections = @(Get-NetTCPConnection -LocalPort $script:cfg['server']['port'] -State Listen -ErrorAction SilentlyContinue)
    $python = [System.IO.Path]::GetFullPath((Join-Path $script:cfg['paths']['gpt_sovits_root'] 'runtime\python.exe'))
    foreach ($connection in $connections) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($connection.OwningProcess)" -ErrorAction SilentlyContinue
        if ($process -and [System.IO.Path]::GetFullPath($process.ExecutablePath) -eq $python) {
            Stop-Process -Id $connection.OwningProcess -Force -ErrorAction SilentlyContinue
        } elseif ($process) {
            throw '朗读端口被其他程序占用，请在高级配置中更换端口。'
        }
    }
    $deadline = [DateTime]::Now.AddSeconds(10)
    while ([DateTime]::Now -lt $deadline) {
        $left = @(Get-NetTCPConnection -LocalPort $script:cfg['server']['port'] -State Listen -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    }
    throw '旧朗读服务未能关闭。'
}

function Start-VoiceService {
    try {
        Set-Busy $true '状态：正在启动朗读服务，请稍候…'
        Stop-VoiceService
        Set-CacheEnvironment $script:cfg
        $root = $script:cfg['paths']['gpt_sovits_root']
        $python = Join-Path $root 'runtime\python.exe'
        if (-not (Test-Path -LiteralPath $python)) { throw '找不到朗读引擎，请检查配置。' }
        $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
        $stdout = Join-Path $script:logDir "service-$stamp.out.log"
        $stderr = Join-Path $script:logDir "service-$stamp.err.log"
        $args = 'api_v2.py -a ' + $script:cfg['server']['host'] + ' -p ' + $script:cfg['server']['port'] +
            ' -c GPT_SoVITS/configs/tts_infer.yaml'
        $script:job = Start-Process -FilePath $python -ArgumentList $args -WorkingDirectory $root `
            -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $script:jobKind = 'service'
        $script:serviceDeadline = [DateTime]::Now.AddMinutes(2)
    } catch {
        $script:job = $null
        Set-Busy $false
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法启动朗读服务',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

function Start-VoiceSwitch([string]$Voice) {
    try {
        Set-Busy $true "状态：正在切换到 $Voice，MAGI 将自动重新打开…"
        Stop-Magi
        Start-HiddenTask -Kind 'switch' -Voice $Voice
    } catch {
        $script:job = $null
        Set-Busy $false
        Start-Magi
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '切换音色失败') | Out-Null
    }
}

function Show-VoicePicker {
    $voices = @(List-Experiments -Root $script:cfg['paths']['gpt_sovits_root'])
    if ($voices.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('还没有可切换的音色，请先训练新音色。', '切换音色') | Out-Null
        return
    }
    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = '选择要使用的音色'
    $picker.Size = New-Object System.Drawing.Size(420, 190)
    $picker.StartPosition = 'CenterParent'
    $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(30, 28)
    $combo.Size = New-Object System.Drawing.Size(345, 30)
    $combo.DropDownStyle = 'DropDownList'
    $combo.Items.AddRange([string[]]$voices)
    $current = $script:cfg['current_voice']['exp_name']
    $combo.SelectedIndex = if ($voices -contains $current) { [Array]::IndexOf([string[]]$voices, $current) } else { 0 }
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '确定切换'
    $ok.Size = New-Object System.Drawing.Size(110, 36)
    $ok.Location = New-Object System.Drawing.Point(145, 82)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $picker.Controls.AddRange(@($combo, $ok))
    $picker.AcceptButton = $ok
    if ($picker.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Start-VoiceSwitch ([string]$combo.SelectedItem)
    }
    $picker.Dispose()
}

function Start-NewTraining {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = '选择用于训练的音频'
    $dialog.Filter = '音频文件|*.wav;*.mp3;*.flac;*.m4a|所有文件|*.*'
    $dialog.InitialDirectory = $script:cfg['paths']['input_dir']
    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { $dialog.Dispose(); return }
    $audio = $dialog.FileName
    $dialog.Dispose()

    $defaultName = 'voice_' + [DateTime]::Now.ToString('MMdd_HHmm')
    $voice = [Microsoft.VisualBasic.Interaction]::InputBox(
        "给新音色起个名字（英文或拼音，例如 xiaoming）。`n建议使用 1～10 分钟、无背景音乐的干净人声。",
        '训练新音色', $defaultName)
    if ([string]::IsNullOrWhiteSpace($voice)) { return }
    $voice = $voice.Trim()
    if ($voice -notmatch '^[A-Za-z0-9_-]+$') {
        [System.Windows.Forms.MessageBox]::Show('名称只能包含英文字母、数字、横线或下划线。', '名称不合适') | Out-Null
        return
    }
    $root = $script:cfg['paths']['gpt_sovits_root']
    $existing = @(List-Experiments -Root $root)
    if ($existing -contains $voice -or (Test-Path -LiteralPath (Join-Path $root "output\asr_opt\$voice.list"))) {
        [System.Windows.Forms.MessageBox]::Show('这个名称已经存在，请换一个名称，避免覆盖已有音色。', '名称已存在') | Out-Null
        return
    }
    try {
        Set-Busy $true '状态：正在处理音频并识别文字，首次处理可能需要下载模型…'
        Start-HiddenTask -Kind 'prepare' -Voice $voice -Audio $audio
    } catch {
        $script:job = $null
        Set-Busy $false
        [System.Windows.Forms.MessageBox]::Show('无法开始处理音频，请确认文件可以正常播放后重试。', '处理失败') | Out-Null
    }
}

function Edit-AdvancedConfig {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "这是高级设置，日常换音色无需修改。`n这里保存本机私有配置，不会提交到 Git。`n保存并关闭记事本后会自动应用；已打开的服务和 MAGI 会重启。`n`n是否继续？",
        '编辑配置', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $wasApi = Test-Api
    $wasMagi = @(Get-MagiProcesses).Count -gt 0
    $localConfig = Join-Path $script:repo 'config\stack.local.yaml'
    if (-not (Test-Path -LiteralPath $localConfig)) {
        Write-Utf8NoBom $localConfig "# 本机私有配置（不入库，切勿提交）。`r`n"
    }
    $notepad = Start-Process -FilePath 'notepad.exe' -ArgumentList (Quote-Arg $localConfig) -PassThru
    $notepad.WaitForExit()
    try {
        Set-Busy $true '状态：正在应用配置…'
        if ($wasApi) { Stop-VoiceService }
        Stop-Magi
        & (Join-Path $script:repo 'scripts\apply-config.ps1') | Out-Null
        $script:cfg = Get-StackConfig
        Set-CacheEnvironment $script:cfg
        Set-Busy $false
        Update-StatusLabels
        if ($wasApi) { Start-VoiceService }
        if ($wasMagi) { Start-Magi }
        if (-not $wasApi) {
            [System.Windows.Forms.MessageBox]::Show('配置已生效。', '编辑配置') | Out-Null
        }
    } catch {
        $script:job = $null
        Set-Busy $false
        [System.Windows.Forms.MessageBox]::Show('配置未能应用，请检查填写内容后重试。' + "`n" + $_.Exception.Message,
            '配置错误', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '音色工坊'
$form.Size = New-Object System.Drawing.Size(650, 505)
$form.MinimumSize = $form.Size
$form.MaximumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 252)

$title = New-Object System.Windows.Forms.Label
$title.Text = '音色工坊'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 22, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(30, 22)
$title.AutoSize = $true
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = '选择音频、训练音色，一键让 MAGI 使用新声音。'
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = New-Object System.Drawing.Point(34, 75)
$subtitle.AutoSize = $true

$labelApi = New-Object System.Windows.Forms.Label
$labelApi.Location = New-Object System.Drawing.Point(35, 112)
$labelApi.Size = New-Object System.Drawing.Size(240, 28)
$labelVoice = New-Object System.Windows.Forms.Label
$labelVoice.Location = New-Object System.Drawing.Point(295, 112)
$labelVoice.Size = New-Object System.Drawing.Size(300, 28)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Location = New-Object System.Drawing.Point(30, 155)
$layout.Size = New-Object System.Drawing.Size(575, 235)
$layout.ColumnCount = 2
$layout.RowCount = 3
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
for ($i = 0; $i -lt 3; $i++) { $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 33.33))) | Out-Null }

$definitions = @(
    @('训练新音色', { Start-NewTraining }),
    @('切换音色', { Show-VoicePicker }),
    @('启动或重启朗读服务', { Start-VoiceService }),
    @('打开 MAGI 阅读器', { try { Start-Magi } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message) | Out-Null } }),
    @('试听', {
        if (-not (Test-Api)) {
            [System.Windows.Forms.MessageBox]::Show('请先启动朗读服务，再试听。', '试听') | Out-Null
        } else {
            try { Set-Busy $true '状态：正在生成试听…'; Start-HiddenTask -Kind 'test' }
            catch { Set-Busy $false; [System.Windows.Forms.MessageBox]::Show('试听未能开始，请重试。') | Out-Null }
        }
    }),
    @('编辑配置', { Edit-AdvancedConfig })
)
foreach ($definition in $definitions) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $definition[0]
    $button.Dock = 'Fill'
    $button.Margin = New-Object System.Windows.Forms.Padding(7)
    $button.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = [System.Drawing.Color]::White
    $button.FlatStyle = 'Flat'
    $action = $definition[1]
    $button.Add_Click($action)
    $layout.Controls.Add($button) | Out-Null
    $script:buttons += $button
}

$labelOperation = New-Object System.Windows.Forms.Label
$labelOperation.Text = '状态：就绪'
$labelOperation.Location = New-Object System.Drawing.Point(35, 405)
$labelOperation.Size = New-Object System.Drawing.Size(565, 38)
$labelOperation.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.AddRange(@($title, $subtitle, $labelApi, $labelVoice, $layout, $labelOperation))

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
    $script:statusTick++
    if ($script:statusTick % 4 -eq 0 -and $null -eq $script:job) { Update-StatusLabels }
    if ($null -eq $script:job) { return }

    if ($script:jobKind -eq 'service') {
        if (Test-Api) {
            $script:job.Dispose()
            $script:job = $null
            Set-Busy $false '状态：朗读服务已启动，可以打开 MAGI 听书。'
            Update-StatusLabels
        } elseif ($script:job.HasExited -or [DateTime]::Now -gt $script:serviceDeadline) {
            $script:job.Dispose()
            $script:job = $null
            Set-Busy $false
            Update-StatusLabels
            [System.Windows.Forms.MessageBox]::Show('朗读服务未能启动，请稍后重试。', '启动失败',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
        return
    }
    if (-not $script:job.HasExited) { return }
    # PowerShell 5 在部分机器上仅查询 HasExited 后，ExitCode 尚未回填。
    $script:job.WaitForExit()

    $kind = $script:jobKind
    $voice = $script:jobVoice
    $succeeded = (Test-Path -LiteralPath $script:jobStatusFile) -and
        ((Get-Content -LiteralPath $script:jobStatusFile -Raw -ErrorAction SilentlyContinue).Trim() -eq 'success')
    $script:job.Dispose()
    $script:job = $null
    Set-Busy $false
    Update-StatusLabels

    if ($kind -eq 'prepare') {
        $list = Join-Path $script:cfg['paths']['gpt_sovits_root'] "output\asr_opt\$voice.list"
        if ($succeeded -and (Test-Path -LiteralPath $list) -and (Get-Item -LiteralPath $list).Length -gt 0) {
            $notepad = Start-Process -FilePath 'notepad.exe' -ArgumentList (Quote-Arg $list) -PassThru
            [System.Windows.Forms.MessageBox]::Show(
                "音频处理完成，已打开校对文本。`n请抽查并修正识别错字，保存后关闭记事本。`n关闭后会询问是否开始训练。",
                '请校对识别文字', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            $notepad.WaitForExit()
            $train = [System.Windows.Forms.MessageBox]::Show('校对完成后，是否现在开始训练？训练期间可以继续使用电脑，但建议关闭游戏和视频软件。',
                '开始训练', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($train -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Set-Busy $true "状态：正在训练 $voice，完成后会自动通知你…"
                    Start-HiddenTask -Kind 'train' -Voice $voice
                } catch {
                    $script:job = $null
                    Set-Busy $false
                    [System.Windows.Forms.MessageBox]::Show('训练未能开始，请重试。', '训练失败') | Out-Null
                }
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show('音频处理未完成。请确认音频清晰且可以正常播放，然后重试。', '处理失败',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } elseif ($kind -eq 'train') {
        if ($succeeded) {
            $switch = [System.Windows.Forms.MessageBox]::Show("音色 $voice 已训练完成！`n是否现在设为当前音色并打开 MAGI？",
                '训练完成', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($switch -eq [System.Windows.Forms.DialogResult]::Yes) { Start-VoiceSwitch $voice }
        } else {
            [System.Windows.Forms.MessageBox]::Show('训练未完成。请关闭游戏、模拟器和视频软件，释放显存后重试。', '训练失败',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } elseif ($kind -eq 'switch') {
        $script:cfg = Get-StackConfig
        Start-Magi
        Update-StatusLabels
        if ($succeeded) {
            Set-Busy $false "状态：已切换到 $voice，MAGI 下次朗读即使用新音色。"
            [System.Windows.Forms.MessageBox]::Show("已切换到 $voice。`nMAGI 已重新打开，可以直接朗读。", '切换完成') | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show('音色切换未完成。请重试；如果 MAGI 没有使用新音色，请点击“启动或重启朗读服务”。',
                '切换未完成', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } elseif ($kind -eq 'test') {
        if ($succeeded) {
            $wav = Join-Path $script:repo 'scripts\test-output.wav'
            $player = New-Object System.Media.SoundPlayer($wav)
            $player.PlaySync()
            $player.Dispose()
            Set-Busy $false '状态：试听完成。'
        } else {
            [System.Windows.Forms.MessageBox]::Show('试听未完成，请重启朗读服务后重试。', '试听失败',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }
})

$form.Add_FormClosing({
    if ($null -ne $script:job -and $script:jobKind -ne 'service') {
        $answer = [System.Windows.Forms.MessageBox]::Show("后台任务仍在运行，关闭窗口不会取消任务，但也无法显示完成通知。`n确定关闭吗？",
            '任务尚未完成', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { $_.Cancel = $true }
    }
})

Update-StatusLabels
$timer.Start()
[void]$form.ShowDialog()
$timer.Stop()
$timer.Dispose()
$form.Dispose()
