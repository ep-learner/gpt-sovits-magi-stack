@echo off
chcp 65001 >nul
REM GPT-SoVITS API launcher. Values come from config\_env.bat.
REM Keep this file ASCII-only for compatibility with Windows cmd.exe.
if not exist "%~dp0..\config\_env.bat" (
    echo First run: generating configuration...
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-config.ps1"
)
if not exist "%~dp0..\config\_env.bat" (
    echo [ERROR] Configuration bootstrap failed. Please run scripts\apply-config.ps1 manually.
    pause
    exit /b 1
)
call "%~dp0..\config\_env.bat"

if not exist "%NUMBA_CACHE_DIR%" mkdir "%NUMBA_CACHE_DIR%"
if not exist "%HF_HOME%" mkdir "%HF_HOME%"
if not exist "%MODELSCOPE_CACHE%" mkdir "%MODELSCOPE_CACHE%"

cd /d "%ROOT%"

netstat -ano | findstr ":%PORT% " | findstr LISTENING >nul
if %errorlevel%==0 (
    echo [ERROR] Port %PORT% is already in use.
    pause
    exit /b 1
)

echo Starting GPT-SoVITS API at %API_BASE% ...
echo Keep this window open while using the voice service.
runtime\python.exe api_v2.py -a %HOST% -p %PORT% -c GPT_SoVITS/configs/tts_infer.yaml
pause
