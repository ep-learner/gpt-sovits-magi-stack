# GPT-SoVITS /tts 接口冒烟测试
# 用法：先运行 start-api.bat 起服务，再执行本脚本验证合成是否成功。
# 注意：PowerShell 里的 curl 是 Invoke-WebRequest 的别名，这里直接用 Invoke-WebRequest。

$ErrorActionPreference = "Stop"

# ===== 配置区 =====
$base   = "http://127.0.0.1:9880"
$ref    = "D:\GPT-SoVITS-stack\GPT-SoVITS-v2pro-20250604\output\slicer_opt\xiangong\仙工开物.wav_0002204160_0002316800.wav"
$prompt = "山外则是群雄争霸，百舸争流。"   # 必须与参考音频实际内容逐字一致
$text   = "大家好，这是一段语音克隆合成测试。"
$lang   = "zh"
$out    = Join-Path $PSScriptRoot "test-output.wav"

$uri = "$base/tts?text=$([uri]::EscapeDataString($text))" +
       "&text_lang=$lang" +
       "&ref_audio_path=$([uri]::EscapeDataString($ref))" +
       "&prompt_text=$([uri]::EscapeDataString($prompt))" +
       "&prompt_lang=$lang" +
       "&media_type=wav"

Write-Host "请求 $base/tts ..."
try {
    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 120
    $f = Get-Item $out
    Write-Host ("成功：生成 {0:N1} KB -> {1}" -f ($f.Length / 1KB), $f.FullName)
} catch {
    Write-Host ("失败：" + $_.Exception.Message)
    Write-Host "排查：确认 start-api.bat 窗口有 'Uvicorn running'；参考音频路径存在且无引号；提示文本与音频一致。"
}
