# -*- coding: utf-8 -*-
# relocate：整合包搬家后，把所有文件里写死的旧绝对路径替换成新路径。
# 用字节级 ASCII 替换，兼容 .list / users.pth 等编码不确定的文件（中文部分原样保留）。
# 用法（一般用默认即可）：
#   relocate.ps1
#   relocate.ps1 -OldRoot D:\old\pkg -NewRoot D:\new\pkg -OldInput D:\old\input -NewInput D:\new\input

param(
    [Parameter(Mandatory = $true)][string]$OldRoot,
    [string]$OldInput,
    [string]$OldMagi,
    [string]$NewRoot,
    [string]$NewInput,
    [string]$NewMagi
)

. (Join-Path $PSScriptRoot 'lib.ps1')
$ErrorActionPreference = 'Stop'

# 新位置默认取当前配置，避免把某台电脑的路径写死在脚本里。
$cfg = Get-StackConfig
if (-not $NewRoot) { $NewRoot = $cfg['paths']['gpt_sovits_root'] }
if (-not $NewInput) { $NewInput = $cfg['paths']['input_dir'] }
if (-not $NewMagi) { $NewMagi = $cfg['paths']['magi_exe'] }

function Get-BytesIndexOf {
    param([byte[]]$Haystack, [byte[]]$Needle, [int]$Start = 0)
    if ($Needle.Length -eq 0) { return -1 }
    for ($i = $Start; $i -le $Haystack.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { return $i }
    }
    return -1
}

function Replace-AsciiBytes {
    param([string]$Path, [string]$Old, [string]$New)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warning "跳过（不存在）: $Path"; return 0 }
    $oldBytes = [System.Text.Encoding]::ASCII.GetBytes($Old)
    $newBytes = [System.Text.Encoding]::ASCII.GetBytes($New)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $count = 0
    $ms = New-Object System.IO.MemoryStream
    $i = 0
    while ($i -le $bytes.Length) {
        $idx = Get-BytesIndexOf $bytes $oldBytes $i
        if ($idx -lt 0) {
            if ($i -lt $bytes.Length) { $ms.Write($bytes, $i, $bytes.Length - $i) }
            break
        }
        if ($idx -gt $i) { $ms.Write($bytes, $i, $idx - $i) }
        $ms.Write($newBytes, 0, $newBytes.Length)
        $count++
        $i = $idx + $oldBytes.Length
    }
    [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
    return $count
}

Write-Host "== relocate ==" -ForegroundColor Cyan
Write-Host "旧根: $OldRoot"
Write-Host "新根: $NewRoot"

# 1) users.pth（写死了旧根的 6 行）
$usersPth = Join-Path $NewRoot 'runtime\Lib\site-packages\users.pth'
$n = Replace-AsciiBytes $usersPth $OldRoot $NewRoot
Write-Host ("users.pth 替换 {0} 处" -f $n)

# 2) output\asr_opt\*.list（每行切片 wav 绝对路径）
$asrDir = Join-Path $NewRoot 'output\asr_opt'
if (Test-Path -LiteralPath $asrDir) {
    $total = 0
    Get-ChildItem -LiteralPath $asrDir -Filter '*.list' -File | ForEach-Object {
        $c = Replace-AsciiBytes $_.FullName $OldRoot $NewRoot
        $total += $c
    }
    Write-Host ("asr_opt\*.list 共替换 {0} 处" -f $total)
} else { Write-Warning "asr_opt 目录不存在: $asrDir" }

# 3) 本机配置（ref_audio 可能含旧根；公共 stack.yaml 不应出现真实音色）
foreach ($cfgFile in @(
    (Join-Path (Get-RepoRoot) 'config\stack.yaml'),
    (Join-Path (Get-RepoRoot) 'config\stack.local.yaml')
)) {
    if (Test-Path -LiteralPath $cfgFile) {
        $n = Replace-AsciiBytes $cfgFile $OldRoot $NewRoot
        Write-Host ("{0} 替换 {1} 处" -f (Split-Path -Leaf $cfgFile), $n)
    }
}

# 4) MAGI library.json（refAudioPath 用了旧根）
$libJson = $cfg['paths']['magi_library_json']
$n = Replace-AsciiBytes $libJson $OldRoot $NewRoot
Write-Host ("library.json 替换 {0} 处" -f $n)

Write-Host "== 完成 ==" -ForegroundColor Green
Write-Host "提示：路径由 dep_root 推导。若依赖目录换了盘，请修改 config\stack.local.yaml 的 dep_root，然后运行 apply-config.ps1。"
