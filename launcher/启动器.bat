@echo off
setlocal
pushd "%~dp0"
for %%F in (*.ps1) do (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%%~fF"
    popd
    exit /b
)
popd
