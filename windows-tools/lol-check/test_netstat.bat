@echo off
:: 防闪退：双击运行时用 cmd /c 包一层，脚本结束后强制暂停
if "%~1"=="__run__" (
    shift
    goto :main
)
cmd /c ""%~f0" __run__"
echo.
echo  ============================================
echo   测试完成，按任意键关闭此窗口...
echo  ============================================
pause >nul
exit /b

:main
setlocal enabledelayedexpansion
title Netstat PID Detection Test

echo ==============================================
echo  Netstat PID Detection Test
echo ==============================================
echo.
echo This test verifies the netstat PID filtering
echo logic used in the LOL server checker.
echo.

:: Get CMD's own PID
set "my_pid="
for /f "tokens=2" %%p in (
    'tasklist /fi "imagename eq cmd.exe" /fo table /nh 2^>nul'
) do (
    if not defined my_pid set "my_pid=%%p"
)

if not defined my_pid (
    echo [FAIL] Cannot get CMD PID
    echo Try running from Command Prompt (not double-click).
    pause
    exit /b 1
)
echo [INFO] CMD PID: %my_pid%
echo.

:: Generate network traffic
echo [INFO] Running nslookup to create connections...
nslookup google.com >nul 2>&1
ping -n 1 127.0.0.1 >nul

echo.
echo ---------- Raw netstat for PID %my_pid% ----------
netstat -ano 2>nul | findstr "%my_pid%"
echo --------------------------------------------------
echo.

:: === CORE DETECTION LOGIC (same as v4c) ===
set "found_ip="
for /f "tokens=3" %%a in (
    'netstat -ano 2^>nul ^| findstr "%my_pid%" ^| findstr /v "127.0.0.1" ^| findstr /v "["'
) do (
    for /f "tokens=1 delims=:" %%i in ("%%a") do (
        echo %%i | findstr /r "^[1-9]" >nul 2>&1
        if !errorlevel! equ 0 if not defined found_ip set "found_ip=%%i"
    )
)

if defined found_ip (
    echo [PASS] External IP detected: %found_ip%
    echo The PID-filtering logic works correctly!
    goto :done
)

:: Fallback: spawn ping to force network connection
echo [INFO] CMD has no external connections. Spawning ping...
start /b ping -t 8.8.8.8 >nul 2>&1
ping -n 2 127.0.0.1 >nul

:: Get ping PID
set "ping_pid="
for /f "tokens=2" %%p in (
    'tasklist /fi "imagename eq PING.EXE" /fo table /nh 2^>nul'
) do (
    if not defined ping_pid set "ping_pid=%%p"
)

if not defined ping_pid (
    echo [FAIL] Cannot spawn ping process
    echo.
    echo Diagnostics - netstat for CMD PID:
    netstat -ano 2>nul | findstr "%my_pid%"
    goto :done
)

echo [INFO] Ping PID: !ping_pid!
echo.
echo ---------- Raw netstat for PID !ping_pid! ----------
netstat -ano 2>nul | findstr "!ping_pid!"
echo -----------------------------------------------------
echo.

:: Run core logic on ping PID
for /f "tokens=3" %%a in (
    'netstat -ano 2^>nul ^| findstr "!ping_pid!" ^| findstr /v "127.0.0.1" ^| findstr /v "["'
) do (
    for /f "tokens=1 delims=:" %%i in ("%%a") do (
        echo %%i | findstr /r "^[1-9]" >nul 2>&1
        if !errorlevel! equ 0 if not defined found_ip set "found_ip=%%i"
    )
)

:: Clean up ping
taskkill /f /pid !ping_pid! >nul 2>&1

if defined found_ip (
    echo [PASS] External IP via ping: !found_ip!
    echo The PID-filtering logic works!
) else (
    echo [FAIL] No external IP detected even with ping.
    echo This may indicate a netstat parsing issue.
    echo Check the raw output above for PID matching.
)

:done
echo.
echo ==============================================
echo Test complete. Press any key to exit.
pause >nul
exit /b 0
