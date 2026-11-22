# GPT-SoVITS /tts 接口冒烟测试
# 用法：先运行 start-api.bat 起服务，再执行本脚本验证合成是否成功。
# 路径/参考音频/提示文本全部来自 config\_env.ps1（由 apply-config 生成）。

$ErrorActionPreference = "Stop"
$envPs1 = Join-Path $PSScriptRoot '..\config\_env.ps1'
if (-not (Test-Path -LiteralPath $envPs1)) {
    & (Join-Path $PSScriptRoot 'apply-config.ps1')
}
. $envPs1

$base   = $cfgApiBase
$ref    = $cfgRefAudio
$prompt = $cfgPromptText
$text   = "大家好，这是一段语音克隆合成测试。"
$lang   = $cfgTextLang
$out    = Join-Path $PSScriptRoot "test-output.wav"

$uri = "$base/tts?text=$([uri]::EscapeDataString($text))" +
       "&text_lang=$lang" +
       "&ref_audio_path=$([uri]::EscapeDataString($ref))" +
       "&prompt_text=$([uri]::EscapeDataString($prompt))" +
       "&prompt_lang=$cfgPromptLang" +
       "&media_type=wav"

Write-Host "请求 $base/tts ..."
try {
    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 120
    $f = Get-Item $out
    Write-Host ("成功：生成 {0:N1} KB -> {1}" -f ($f.Length / 1KB), $f.FullName)
} catch {
    Write-Host ("失败：" + $_.Exception.Message)
    Write-Host "排查：确认朗读服务已启动；参考音频路径存在且无引号；提示文本与音频一致。"
    throw
}
