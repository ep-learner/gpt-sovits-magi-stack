# -*- coding: utf-8 -*-
# 音色工坊共享库：配置读取、权重解析、文件写入。
# 被 apply-config.ps1 / switch-voice.ps1 / 启动器 dot-source。
# 所有路径以仓库根为基准。

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Unquote-YamlValue([string]$v) {
    if ($null -eq $v) { return '' }
    $v = $v.Trim()
    if ($v.Length -ge 2 -and (
            ($v.StartsWith('"') -and $v.EndsWith('"')) -or
            ($v.StartsWith("'") -and $v.EndsWith("'")))) {
        return $v.Substring(1, $v.Length - 2)
    }
    return $v
}

# 极简 YAML 读取（仅支持本仓库 stack.yaml 的两层结构 + 标量值）
function Read-StackYaml {
    param([string]$Path)
    $result = [ordered]@{}
    $section = $null
    foreach ($raw in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $t = $raw.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($raw -match '^(\w[\w_]*)\s*:\s*(.*)$') {
            $key = $matches[1]
            $val = $matches[2].Trim()
            if ($val -eq '') {
                $section = [ordered]@{}
                $result[$key] = $section
            } else {
                $section = $null
                $result[$key] = Unquote-YamlValue $val
            }
        } elseif ($raw -match '^  (\w[\w_]*)\s*:\s*(.*)$') {
            if ($null -ne $section) {
                $section[$matches[1]] = Unquote-YamlValue $matches[2]
            }
        }
    }
    return $result
}

# 浅合并：override 的同名字段覆盖 base；都是子表时合并子字段
function Merge-Hashtable($base, $override) {
    $out = [ordered]@{}
    foreach ($k in $base.Keys) { $out[$k] = $base[$k] }
    foreach ($k in $override.Keys) {
        if ($out.Contains($k) -and $out[$k] -is [System.Collections.Specialized.OrderedDictionary] -and $override[$k] -is [System.Collections.Specialized.OrderedDictionary]) {
            foreach ($sk in $override[$k].Keys) { $out[$k][$sk] = $override[$k][$sk] }
        } else {
            $out[$k] = $override[$k]
        }
    }
    return $out
}

# 展开 ${VAR} / %VAR% / ~ 等写法
function Expand-ConfigValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $v = $Value.Trim()
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $name = $m.Groups[1].Value
        $envValue = [Environment]::GetEnvironmentVariable($name)
        if ($null -eq $envValue) { $envValue = [Environment]::GetEnvironmentVariable($name, 'User') }
        if ($null -eq $envValue) { $envValue = [Environment]::GetEnvironmentVariable($name, 'Machine') }
        if ($null -eq $envValue) { return '' }
        return $envValue
    }
    $v = [regex]::Replace($v, '\$\{([^}]+)\}', $evaluator)
    $v = [regex]::Replace($v, '%([^%]+)%', $evaluator)
    if ($v -eq '~') { $v = $env:USERPROFILE }
    elseif ($v.StartsWith('~\') -or $v.StartsWith('~/')) { $v = Join-Path $env:USERPROFILE $v.Substring(2) }
    return $v
}

# 把配置里的值解析成绝对路径：先展开变量，相对路径再拼到 Base
function Resolve-ConfigPath {
    param([string]$Value, [string]$Base)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $v = Expand-ConfigValue $Value
    if ([string]::IsNullOrWhiteSpace($v)) { return '' }
    if (-not [System.IO.Path]::IsPathRooted($v)) { $v = Join-Path $Base $v }
    return [System.IO.Path]::GetFullPath($v)
}

# 写回配置时尽量存相对 Root 的路径，保证换电脑后仍可用
function ConvertTo-RootRelativePath {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $p = [System.IO.Path]::GetFullPath($Path)
    $r = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($p.StartsWith($r + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $p.Substring($r.Length + 1)
    }
    return $p
}

# 读取合并后的完整配置，并把相对路径解析成当前机器的绝对路径
function Get-StackConfig {
    $root = Get-RepoRoot
    $main = Join-Path $root 'config\stack.yaml'
    if (-not (Test-Path -LiteralPath $main)) { throw "缺少配置文件: $main" }
    $cfg = Read-StackYaml $main
    $local = Join-Path $root 'config\stack.local.yaml'
    if (Test-Path -LiteralPath $local) {
        $cfg = Merge-Hashtable $cfg (Read-StackYaml $local)
    }

    $depRaw = if ($cfg.Contains('dep_root')) { [string]$cfg['dep_root'] } else { '' }
    if ([string]::IsNullOrWhiteSpace($depRaw)) { $depRaw = '..\aiVoiceDep' }
    $dep = Resolve-ConfigPath $depRaw $root
    $cfg['dep_root'] = $dep

    $paths = $cfg['paths']
    foreach ($key in @('gpt_sovits_root', 'magi_exe', 'magi_library_json', 'input_dir')) {
        if ($paths.Contains($key)) { $paths[$key] = Resolve-ConfigPath $paths[$key] $dep }
    }
    $cache = $cfg['cache']
    foreach ($key in @('huggingface', 'modelscope', 'numba')) {
        if ($cache.Contains($key)) { $cache[$key] = Resolve-ConfigPath $cache[$key] $dep }
    }

    # 参考音频相对整合包根目录保存，便于跟随整合包一起迁移
    $cv = $cfg['current_voice']
    if ($cv.Contains('ref_audio') -and -not [string]::IsNullOrWhiteSpace($cv['ref_audio'])) {
        $cv['ref_audio'] = Resolve-ConfigPath $cv['ref_audio'] $paths['gpt_sovits_root']
    }

    # 派生字段
    $cfg['paths']['api_base'] = "http://$($cfg['server']['host']):$($cfg['server']['port'])"
    return $cfg
}

# 取某实验最新的 SoVITS / GPT 权重（相对整合包根的路径）
function Get-LatestWeights {
    param([string]$Root, [string]$Exp)
    $sovDir = Join-Path $Root 'SoVITS_weights_v2Pro'
    $gptDir = Join-Path $Root 'GPT_weights_v2Pro'
    $s = Get-ChildItem -LiteralPath $sovDir -Filter "$Exp`_*.pth" -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $g = Get-ChildItem -LiteralPath $gptDir -Filter "$Exp-*.ckpt" -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $s) { throw "找不到 SoVITS 权重: $sovDir\$Exp`_*.pth" }
    if (-not $g) { throw "找不到 GPT 权重: $gptDir\$Exp-*.ckpt" }
    return [ordered]@{
        sovits_rel = "SoVITS_weights_v2Pro/$($s.Name)"
        gpt_rel    = "GPT_weights_v2Pro/$($g.Name)"
        sovits_full = $s.FullName
        gpt_full    = $g.FullName
    }
}

# 列出所有已训练实验（有对应权重的）
function List-Experiments {
    param([string]$Root)
    $names = @{}
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Root 'SoVITS_weights_v2Pro') -Filter '*.pth' -ErrorAction SilentlyContinue) {
        if ($f.BaseName -match '^(.+?)_e\d+') { $names[$matches[1]] = $true }
    }
    return $names.Keys | Sort-Object
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

# 更新本机私有配置的 current_voice 段。必须写 stack.local.yaml：
# stack.yaml 是入库的公共默认，绝不能写入真实音色名/参考音频/提示文本。
function Update-StackCurrentVoice {
    param(
        [string]$Repo, [string]$Exp, [string]$RefAudio,
        [string]$PromptText, [string]$TextLang, [string]$PromptLang
    )
    $path = Join-Path $Repo 'config\stack.local.yaml'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Utf8NoBom $path "# 本机私有配置（不入库，切勿提交）。`r`n"
    }
    $txt = [System.IO.File]::ReadAllText($path)
    $block = @"
current_voice:
  exp_name: $Exp
  ref_audio: $RefAudio
  prompt_text: $PromptText
  text_lang: $TextLang
  prompt_lang: $PromptLang
"@
    $pattern = '(?ms)^current_voice:\r?\n(?:[ \t]+.*\r?\n)*'
    if ([regex]::IsMatch($txt, '(?m)^current_voice:')) {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block + "`r`n" }
        $newTxt = [regex]::Replace($txt, $pattern, $evaluator)
    } else {
        if ($txt.Length -gt 0 -and -not $txt.EndsWith("`n")) { $txt += "`r`n" }
        $newTxt = $txt + "`r`n" + $block
    }
    Write-Utf8NoBom $path $newTxt
}

# 带 BOM：PowerShell 5.1 读含中文的 .ps1 必须有 BOM，否则按 ANSI 解码会乱码
function Write-Utf8Bom {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}
