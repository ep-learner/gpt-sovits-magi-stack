# -*- coding: utf-8 -*-
# switch-voice：一键切换当前音色并让 MAGI 生效。
# 用法：
#   switch-voice.ps1 -List                  # 列出已训练的音色
#   switch-voice.ps1 -Exp myvoice           # 切到 myvoice（自动选最新权重 + 3~6s 参考切片）
#   switch-voice.ps1 -Exp xxxx -RefAudio <wav> -PromptText "..."  # 手动指定参考音频/提示文本
# 副作用：更新不入库的 config\stack.local.yaml → 调 apply-config 同步 tts_infer.yaml + library.json →
#         若 API 在运行则热切换权重，否则下次启动 API 自动加载。

param(
    [string]$Exp,
    [switch]$List,
    [string]$RefAudio,
    [string]$PromptText,
    [string]$TextLang = 'zh',
    [string]$PromptLang = 'zh'
)

. (Join-Path $PSScriptRoot 'lib.ps1')
$ErrorActionPreference = 'Stop'

$repo = Get-RepoRoot
$cfg = Get-StackConfig
$root = $cfg['paths']['gpt_sovits_root']
$apiBase = $cfg['paths']['api_base']

if ($List) {
    $exps = List-Experiments -Root $root
    if ($exps) { $exps | ForEach-Object { Write-Output $_ } } else { Write-Output '（暂无已训练的音色）' }
    return
}
if (-not $Exp) { throw '请指定 -Exp <实验名>，或用 -List 查看可用音色' }

Write-Host "== 切换音色 -> $Exp ==" -ForegroundColor Cyan

# 1) 最新权重
$w = Get-LatestWeights -Root $root -Exp $Exp
Write-Host "SoVITS 权重: $($w['sovits_rel'])"
Write-Host "GPT 权重   : $($w['gpt_rel'])"

# 2) 参考音频 + 提示文本（未手动指定则从 .list 自动挑一条 3~6 秒的）
# 重复选择当前音色时保留已校对的参考片段，避免被自动选片覆盖。
$current = $cfg['current_voice']
if (-not $RefAudio -and $current['exp_name'] -eq $Exp -and
    $current['ref_audio'] -and (Test-Path -LiteralPath $current['ref_audio']) -and $current['prompt_text']) {
    $RefAudio = $current['ref_audio']
    if (-not $PromptText) { $PromptText = $current['prompt_text'] }
    Write-Host "保留当前参考音频: $RefAudio"
}
if (-not $RefAudio) {
    $listPath = Join-Path $root "output\asr_opt\$Exp.list"
    if (Test-Path -LiteralPath $listPath) {
        $ffprobe = Join-Path $root 'runtime\ffprobe.exe'
        $hasFf = Test-Path -LiteralPath $ffprobe
        $picked = $null
        foreach ($line in Get-Content -LiteralPath $listPath -Encoding UTF8) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\|', 4
            if ($parts.Count -lt 4) { continue }
            $wav = $parts[0]; $txt = $parts[3]
            if (-not (Test-Path -LiteralPath $wav)) { continue }
            $dur = $null
            if ($hasFf) {
                $out = & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $wav 2>$null
                if ($out -and [double]::TryParse($out, [ref]$null)) { $dur = [double]$out }
            }
            if ($null -eq $dur -or ($dur -ge 3.0 -and $dur -le 6.0)) {
                $picked = [ordered]@{ wav = $wav; txt = $txt; dur = $dur }
                break
            }
        }
        if ($picked) {
            $RefAudio = $picked.wav
            if (-not $PromptText) { $PromptText = $picked.txt }
            $d = if ($picked.dur) { "{0:N1}s" -f $picked.dur } else { '未知' }
            Write-Host "自动选参考音频: $($picked.wav) (时长 $d)"
        }
    }
}
if (-not $RefAudio) { throw "找不到实验 $Exp 的参考音频（output\asr_opt\$Exp.list 不存在或无可用切片）。请用 -RefAudio 手动指定。" }
if (-not $PromptText) { $PromptText = '（请在 config\stack.yaml 填写与参考音频逐字一致的提示文本）' }
Write-Host "参考音频: $RefAudio"
Write-Host "提示文本: $PromptText"

# 3) 更新 stack.yaml + apply-config（同步两端）
# 参考音频在整合包内时存相对路径，迁移到别的电脑后仍能定位。
$refStored = ConvertTo-RootRelativePath -Path $RefAudio -Root $root
Update-StackCurrentVoice -Repo $repo -Exp $Exp -RefAudio $refStored `
    -PromptText $PromptText -TextLang $TextLang -PromptLang $PromptLang
& (Join-Path $PSScriptRoot 'apply-config.ps1') | Out-Null
Write-Host "stack.local.yaml（不入库）/ tts_infer.yaml / library.json 已同步" -ForegroundColor Green

# 4) 若 API 在运行则热切换；否则提示下次启动自动加载
$alive = $false
try {
    Invoke-WebRequest -Uri $apiBase -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop | Out-Null
    $alive = $true
} catch {
    # 有任何 HTTP 响应（含 404/405）都算服务在
    if ($_.Exception.Response) { $alive = $true }
}
if ($alive) {
    Write-Host "API 运行中，热切换权重..."
    try {
        Invoke-WebRequest -Uri "$apiBase/set_sovits_weights?weights_path=$($w['sovits_rel'])" -UseBasicParsing -TimeoutSec 90 | Out-Null
        Invoke-WebRequest -Uri "$apiBase/set_gpt_weights?weights_path=$($w['gpt_rel'])" -UseBasicParsing -TimeoutSec 180 | Out-Null
        Write-Host "热切换完成，MAGI 下次朗读即为新音色。" -ForegroundColor Green
    } catch {
        Write-Warning "热切换失败: $($_.Exception.Message)。请重启朗读服务后重试。"
        throw
    }
} else {
    Write-Host "API 当前未运行。tts_infer.yaml 已指向新权重，下次双击 start-api.bat 启动即自动加载。" -ForegroundColor Yellow
}
Write-Host "== 完成 ==" -ForegroundColor Green
