@echo off
echo ========================================================
echo   Compiling UHF Hardware Bridge Service (x86 Release)
echo ========================================================

set CSC="C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"

cd /d "%~dp0"
if not exist "bin\Release" mkdir "bin\Release"
copy /y "libs\*" "bin\Release\" >nul

%CSC% /target:exe /platform:x86 /out:bin\Release\UHFHardwareBridge.exe /reference:System.Web.Extensions.dll /reference:libs\RFIDReaderAPI.dll UHFHardwareBridge.cs

if %ERRORLEVEL% equ 0 (
    echo.
    echo ========================================================
    echo   BUILD SUCCESSFUL!
    echo   Output: %~dp0bin\Release\UHFHardwareBridge.exe
    echo ========================================================
) else (
    echo.
    echo [ERROR] Build failed! Please check error output above.
)
