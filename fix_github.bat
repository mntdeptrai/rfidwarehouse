@echo off
chcp 65001 >nul
:: Tu dong yeu cau quyen Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Dang yeu cau quyen Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ======================================================
echo    DANG SUA LOI TIMEOUT GITHUB (PORT 443)
echo ======================================================

set "HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts"

:: Xoa cac dong github cu neu co va them IP moi hoat dong tot
findstr /C:"140.82.121.4 github.com" "%HOSTS_FILE%" >nul 2>&1
if %errorlevel% equ 0 (
    echo IP GitHub tối ưu đã có sẵn trong file hosts!
) else (
    echo. >> "%HOSTS_FILE%"
    echo # Fix GitHub Connection Timeout >> "%HOSTS_FILE%"
    echo 140.82.121.4 github.com >> "%HOSTS_FILE%"
    echo 140.82.121.4 www.github.com >> "%HOSTS_FILE%"
    echo 140.82.112.4 assets-cdn.github.com >> "%HOSTS_FILE%"
    echo 185.199.108.133 raw.githubusercontent.com >> "%HOSTS_FILE%"
    echo 185.199.108.133 objects.githubusercontent.com >> "%HOSTS_FILE%"
    echo [OK] Đã ghi IP GitHub vào file hosts.
)

echo Dang xoa cache DNS...
ipconfig /flushdns >nul
echo [OK] Đã làm mới DNS resolver cache.

echo.
echo ======================================================
echo    ĐÃ SỬA XONG! BÂY GIỜ BẠN CÓ THỂ GIT PULL BÌNH THƯỜNG.
echo ======================================================
pause
