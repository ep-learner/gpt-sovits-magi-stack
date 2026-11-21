@echo off
chcp 65001 >nul
REM ============================================================
REM  一键启动 GPT-SoVITS API 服务（端口 9880）
REM  训练完成后，MAGI 阅读器连接的就是这个服务（不是 WebUI）。
REM ============================================================

REM ===== 配置区：如路径/端口变动请修改这里 =====
set "ROOT=D:\GPT-SoVITS-stack\GPT-SoVITS-v2pro-20250604"
set "PORT=9880"
set "NUMBA_CACHE_DIR=%LOCALAPPDATA%\Temp\numba_cache"

REM numba 缓存重定向到可写目录，避免嵌入 Python 下 librosa/numba 缓存报错
if not exist "%NUMBA_CACHE_DIR%" mkdir "%NUMBA_CACHE_DIR%"

cd /d "%ROOT%"

REM 端口占用检查：避免起出两个实例打架
netstat -ano | findstr ":%PORT% " | findstr LISTENING >nul
if %errorlevel%==0 (
    echo [错误] 端口 %PORT% 已被占用。请先关闭占用进程，或修改本文件中的 PORT。
    pause
    exit /b 1
)

echo 启动 GPT-SoVITS API 服务...
echo 地址: http://127.0.0.1:%PORT%   （看到 "Uvicorn running" 即成功，窗口勿关）
runtime\python.exe api_v2.py -a 127.0.0.1 -p %PORT% -c GPT_SoVITS/configs/tts_infer.yaml
pause
