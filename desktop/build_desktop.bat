@echo off
echo ========================================================
echo   Compiling UHF RFID Desktop Suite (Windows x86 Release)
echo ========================================================

set MSBUILD="C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
if not exist %MSBUILD% (
    set MSBUILD="C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
)

cd /d "%~dp0"
%MSBUILD% UHFDesktopApp.csproj /p:Configuration=Release /p:Platform=x86 /t:Rebuild

if %ERRORLEVEL% equ 0 (
    echo.
    echo ========================================================
    echo   BUILD SUCCESSFUL!
    echo   Output executable: %~dp0bin\Release\UHFDesktopApp.exe
    echo ========================================================
) else (
    echo.
    echo [ERROR] Build failed! Please check error output above.
)
