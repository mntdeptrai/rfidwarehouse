@echo off
chcp 65001 >nul
title Khởi Động Kho RFID WMS
cd /d "%~dp0"

:: 1. Tự động kiểm tra và cài đặt ngầm runtime nếu máy mới chưa cài
reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" /v Installed >nul 2>&1
if %errorlevel% neq 0 (
    if exist "vc_redist.x64.exe" (
        start /wait vc_redist.x64.exe /install /quiet /norestart
    )
)

:: 2. Khởi chạy ứng dụng ngay lập tức
start "" "%~dp0uhf.exe"
exit
