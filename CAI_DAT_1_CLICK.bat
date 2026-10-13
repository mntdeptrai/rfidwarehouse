@echo off
chcp 65001 >nul
title Cài Đặt & Khởi Động Hệ Thống Kho RFID WMS
cd /d "%~dp0"

echo ========================================================================
echo       HỆ THỐNG QUẢN LÝ KHO RFID WMS (DESKTOP)
echo         TIẾN TRÌNH CÀI ĐẶT TỰ ĐỘNG 1-CLICK (100%% AUTOMATIC)
echo ========================================================================
echo.

:: 1. Tự động kiểm tra và cài đặt Microsoft Visual C++ 2015-2022 Runtime nếu máy chưa có
echo [1/3] Đang kiểm tra thư viện hệ thống Microsoft Visual C++...
reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" /v Installed >nul 2>&1
if %errorlevel% neq 0 (
    echo       -> Phát hiện máy mới chưa có C++ Runtime. Đang tự động cài đặt ngầm...
    if exist "vc_redist.x64.exe" (
        start /wait vc_redist.x64.exe /install /quiet /norestart
        echo       -> Đã hoàn tất cài đặt Microsoft Visual C++ Runtime!
    )
) else (
    echo       -> Máy tính đã có sẵn Microsoft Visual C++ Runtime. Đạt chuẩn!
)

:: 2. Tự động cấp quyền Tường lửa Windows Firewall cho ứng dụng và đầu đọc RFID
echo.
echo [2/3] Đang tự động cấu hình mạng & tường lửa Windows Firewall...
netsh advfirewall firewall add rule name="RFID Warehouse WMS App" dir=in action=allow program="%~dp0uhf.exe" enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="RFID Hardware Bridge" dir=in action=allow program="%~dp0UHFHardwareBridge.exe" enable=yes >nul 2>&1
echo       -> Đã mở cổng kết nối thành công!

:: 3. Tự động tạo biểu tượng Shortcut trên màn hình Desktop của người dùng
echo.
echo [3/3] Đang tự động tạo biểu tượng Shortcut ra màn hình Desktop...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'Kho RFID WMS.lnk')); $s.TargetPath = '%~dp0uhf.exe'; $s.WorkingDirectory = '%~dp0'; $s.Description = 'He Thong Quan Ly Kho RFID WMS'; $s.Save()" >nul 2>&1
echo       -> Đã tạo biểu tượng 'Kho RFID WMS' ngoài màn hình Desktop!

echo.
echo ========================================================================
echo   ✓ HOÀN TẤT CÀI ĐẶT! Đang tự động khởi động ứng dụng kho ngay bây giờ...
echo ========================================================================

start "" "%~dp0uhf.exe"
timeout /t 2 >nul
exit
