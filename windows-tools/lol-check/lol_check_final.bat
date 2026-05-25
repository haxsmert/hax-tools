@echo off
setlocal enabledelayedexpansion
title LOL Server Check [Nanjing Telecom]
mode con cols=75 lines=50

echo ==============================================
echo  LOL Server Check  [Nanjing Telecom Edition]
echo ==============================================
echo.
echo Checking League of Legends process...
echo.

tasklist /fi "imagename eq League of Legends.exe" 2>nul | findstr /i "League" >nul
if %errorlevel% neq 0 (
    echo [FAIL] League of Legends process not found
    echo.
    echo Run this script while IN-GAME (loading screen or match)
    echo Champion select does NOT create game server connections
    echo.
    pause
    exit /b 1
)
echo [OK] League of Legends process found
echo.

:: Get PID via tasklist CSV format
for /f "tokens=2 delims=," %%p in (
    'tasklist /fi "imagename eq League of Legends.exe" /fo csv /nh 2^>nul'
) do (
    set "lol_pid=%%~p"
    goto :got_pid
)
:got_pid

if not defined lol_pid (
    echo [FAIL] Cannot get PID. Try running as Administrator
    echo.
    pause
    exit /b 1
)
echo Getting game server connection info (PID=%lol_pid%)...
echo.

:: === IP检测（双方案）===
:: 根本原因：LOL使用UDP(enet)，Windows netstat对UDP连接远端地址只显示*:*
:: 方案1（主）：从LOL进程命令行参数读取 -ServerIP（最可靠）
:: 方案2（备）：netstat扫TCP连接（部分场景LOL有TCP辅助连接）

set "server_ip="

echo [INFO] 方案1 - 从进程启动参数提取 -ServerIP ...
for /f "tokens=1* delims==" %%a in (
    'wmic process where "name=''League of Legends.exe''" get commandline /format:list 2^>nul'
) do (
    if /i "%%a"=="CommandLine" if not defined server_ip (
        set "_c=%%b"
        echo !_c! | findstr /i "ServerIP" >nul 2>&1
        if !errorlevel! equ 0 (
            set "_a=!_c:*-ServerIP =!"
            set "_a=!_a:"=!"
            for /f "tokens=1" %%x in ("!_a!") do (
                echo %%x | findstr /r "^[1-9][0-9]*\.[0-9]" >nul 2>&1
                if !errorlevel! equ 0 set "server_ip=%%x"
            )
        )
    )
)

if not defined server_ip (
    echo [INFO] 方案2 - netstat扫描TCP建立连接 ^(PID=%lol_pid%^)...
    for /f "tokens=3" %%a in (
        'netstat -ano 2^>nul ^| findstr " %lol_pid%" ^| findstr "TCP" ^| findstr "ESTABLISHED" ^| findstr /v "127.0.0.1" ^| findstr /v "["'
    ) do (
        for /f "tokens=1 delims=:" %%i in ("%%a") do (
            echo %%i | findstr /r "^[1-9][0-9]*\.[0-9]" >nul 2>&1
            if !errorlevel! equ 0 if not defined server_ip set "server_ip=%%i"
        )
    )
)

if not defined server_ip (
    echo [FAIL] 未检测到游戏服务器连接
    echo.
    echo 根本原因：
    echo   LOL使用UDP^(enet^)，netstat对UDP只显示*:*无法获取远端IP
    echo   wmic方法未找到 -ServerIP 参数
    echo.
    echo 请确认：
    echo   1. 脚本须在对局中运行（加载画面或游戏进行中）
    echo   2. 英雄选择/大厅阶段游戏客户端尚未启动
    echo   3. 如仍失败请以管理员身份运行
    echo.
    pause
    exit /b 1
)
echo [OK] Game server IP: %server_ip%
echo.
echo Testing network latency (ICMP x4)...
echo.

:: Match both "Average" and Chinese ping output
set "ping_delay=Timeout"
for /f "tokens=*" %%b in (
    'ping -n 4 %server_ip% 2^>nul ^| findstr /c:"Average" /c:"平均"'
) do (
    for %%c in (%%b) do set "ping_delay=%%c"
)

:: Validate ping result
set "ping_ok=0"
echo %ping_delay% | findstr /r "[0-9][0-9]*ms" >nul 2>&1
if %errorlevel% equ 0 set "ping_ok=1"
if "%ping_ok%"=="0" (
    echo [WARN] No ICMP response, server may block ping
    set "ping_delay=N/A"
)

:: ============================================================
:: IP range lookup table (one findstr per range for reliability)
:: Rating (Nanjing Telecom user perspective):
::   [BEST] Nanjing local Telecom node, shortest physical path
::   [OK] Same or neighboring province, acceptable latency
::   [BAD] Remote cross-province node, high/unstable latency
:: ============================================================

set "server_type=Unknown"
set "server_location=Unknown"
set "server_region=Unknown"
set "server_games=Unknown"
set "ingame_offset=Unknown"
set "quality_mark=[Unknown]"
set "quality_tip=No record for this IP range"

:: === Nanjing Nodes ===

echo %server_ip% | findstr "180.102.58." >nul
if %errorlevel% equ 0 (
    set "server_type=Nanjing Core Node A"
    set "server_location=Nanjing, Jiangsu / Telecom"
    set "server_region=Nanjing"
    set "server_games=Piltover, JiaoYuan, YingLiu, ShouWang"
    set "ingame_offset=+3~5ms"
    set "quality_mark=[BEST]"
    set "quality_tip=Same city, same ISP -- lowest physical latency"
    goto :identify_done
)
echo %server_ip% | findstr "180.102.59." >nul
if %errorlevel% equ 0 (
    set "server_type=Nanjing Core Node B"
    set "server_location=Nanjing, Jiangsu / Telecom"
    set "server_region=Nanjing"
    set "server_games=Piltover, JiaoYuan, YingLiu, ShouWang"
    set "ingame_offset=+3~5ms"
    set "quality_mark=[BEST]"
    set "quality_tip=Same city, same ISP -- lowest physical latency"
    goto :identify_done
)
echo %server_ip% | findstr "114.221.151." >nul
if %errorlevel% equ 0 (
    set "server_type=Nanjing Edge Node A"
    set "server_location=Nanjing, Jiangsu / Telecom"
    set "server_region=Nanjing"
    set "server_games=Ionia (peak expansion)"
    set "ingame_offset=+15~20ms"
    set "quality_mark=[OK]"
    set "quality_tip=Nanjing local but edge routing, higher latency"
    goto :identify_done
)
echo %server_ip% | findstr "114.221.152." >nul
if %errorlevel% equ 0 (
    set "server_type=Nanjing Edge Node B"
    set "server_location=Nanjing, Jiangsu / Telecom"
    set "server_region=Nanjing"
    set "server_games=Ionia (peak expansion)"
    set "ingame_offset=+15~20ms"
    set "quality_mark=[OK]"
    set "quality_tip=Nanjing local but edge routing, higher latency"
    goto :identify_done
)
echo %server_ip% | findstr "42.186.56." >nul
if %errorlevel% equ 0 (
    set "server_type=Nanjing Unicom Node"
    set "server_location=Nanjing, Jiangsu / Unicom"
    set "server_region=Nanjing"
    set "server_games=Ionia (Unicom users)"
    set "ingame_offset=+8~12ms"
    set "quality_mark=[OK]"
    set "quality_tip=Same city, cross-ISP: Telecom-Unicom peering latency"
    goto :identify_done
)

:: === East China Nodes ===

echo %server_ip% | findstr "180.163." >nul
if %errorlevel% equ 0 (
    set "server_type=Shanghai Telecom Primary"
    set "server_location=Shanghai / Telecom"
    set "server_region=Shanghai"
    set "server_games=Ionia, Zaun"
    set "ingame_offset=+8~12ms"
    set "quality_mark=[OK]"
    set "quality_tip=~300km from Nanjing, acceptable latency"
    goto :identify_done
)
echo %server_ip% | findstr "140.206." >nul
if %errorlevel% equ 0 (
    set "server_type=Shanghai电信备用节点"
    set "server_location=Shanghai / Telecom"
    set "server_region=Shanghai"
    set "server_games=Ionia, Zaun"
    set "ingame_offset=+8~12ms"
    set "quality_mark=[OK]"
    set "quality_tip=~300km from Nanjing, acceptable latency"
    goto :identify_done
)
echo %server_ip% | findstr "101.91." >nul
if %errorlevel% equ 0 (
    set "server_type=Shanghai腾讯云节点"
    set "server_location=Shanghai / 腾讯云"
    set "server_region=Shanghai"
    set "server_games=Ionia, Zaun（腾讯云）"
    set "ingame_offset=+8~12ms"
    set "quality_mark=[OK]"
    set "quality_tip=~300km from Nanjing, acceptable latency"
    goto :identify_done
)
echo %server_ip% | findstr "58.215." >nul
if %errorlevel% equ 0 (
    set "server_type=Jiangsu Telecom Node"
    set "server_location=Jiangsu / Telecom"
    set "server_region=Shanghai"
    set "server_games=Multiple servers"
    set "ingame_offset=+5~8ms"
    set "quality_mark=[OK]"
    set "quality_tip=Same-province Telecom, low latency"
    goto :identify_done
)
echo %server_ip% | findstr "49.64." >nul
if %errorlevel% equ 0 (
    set "server_type=Jiangsu Telecom Backup"
    set "server_location=Jiangsu / Telecom"
    set "server_region=Shanghai"
    set "server_games=Multiple servers"
    set "ingame_offset=+5~8ms"
    set "quality_mark=[OK]"
    set "quality_tip=Same-province Telecom, low latency"
    goto :identify_done
)

:: === Guangdong Nodes ===

echo %server_ip% | findstr "113.105." >nul
if %errorlevel% equ 0 (
    set "server_type=Dongguan Telecom Node"
    set "server_location=Dongguan, Guangdong / Telecom"
    set "server_region=Guangdong"
    set "server_games=Black Rose, Noxus"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=~1200km from Nanjing, unstable peak hours"
    goto :identify_done
)
echo %server_ip% | findstr "119.147." >nul
if %errorlevel% equ 0 (
    set "server_type=Guangzhou Telecom Primary"
    set "server_location=Guangdong广州 / 电信"
    set "server_region=Guangdong"
    set "server_games=Black Rose, Noxus"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=~1100km from Nanjing, unstable peak hours"
    goto :identify_done
)
echo %server_ip% | findstr "58.251." >nul
if %errorlevel% equ 0 (
    set "server_type=Guangzhou Telecom Backup"
    set "server_location=Guangdong广州 / 电信"
    set "server_region=Guangdong"
    set "server_games=Multiple servers"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=~1100km from Nanjing, unstable peak hours"
    goto :identify_done
)
echo %server_ip% | findstr "61.151." >nul
if %errorlevel% equ 0 (
    set "server_type=广州电信三期节点"
    set "server_location=Guangdong广州 / 电信"
    set "server_region=Guangdong"
    set "server_games=Multiple servers"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=~1100km from Nanjing, unstable peak hours"
    goto :identify_done
)
echo %server_ip% | findstr "119.29." >nul
if %errorlevel% equ 0 (
    set "server_type=深圳腾讯云节点"
    set "server_location=Guangdong深圳 / 腾讯云"
    set "server_region=Guangdong"
    set "server_games=Multiple servers（腾讯云）"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=距南京约1300km，延迟较高"
    goto :identify_done
)
echo %server_ip% | findstr "203.205." >nul
if %errorlevel% equ 0 (
    set "server_type=深圳腾讯IDC节点"
    set "server_location=Guangdong深圳 / 腾讯IDC"
    set "server_region=Guangdong"
    set "server_games=Multiple servers"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=距南京约1300km，延迟较高"
    goto :identify_done
)

:: === 西南节点 ===

echo %server_ip% | findstr "182.254." >nul
if %errorlevel% equ 0 (
    set "server_type=成都腾讯云节点"
    set "server_location=四川成都 / 腾讯云"
    set "server_region=西南"
    set "server_games=Multiple servers（西南）"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=距南京约1700km，延迟高"
    goto :identify_done
)
echo %server_ip% | findstr "103.7.30." >nul
if %errorlevel% equ 0 (
    set "server_type=重庆腾讯节点"
    set "server_location=重庆 / 腾讯"
    set "server_region=西南"
    set "server_games=Multiple servers（西南）"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=距南京约1500km，延迟高"
    goto :identify_done
)

:: === 华北节点 ===

echo %server_ip% | findstr "111.230." >nul
if %errorlevel% equ 0 (
    set "server_type=天津腾讯云节点"
    set "server_location=天津 / 腾讯云"
    set "server_region=华北"
    set "server_games=Multiple servers（华北）"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=距南京约1000km，绕道华北延迟高"
    goto :identify_done
)
echo %server_ip% | findstr "111.231." >nul
if %errorlevel% equ 0 (
    set "server_type=北京腾讯云节点"
    set "server_location=北京 / 腾讯云"
    set "server_region=华北"
    set "server_games=Multiple servers（华北）"
    set "ingame_offset=+10~15ms"
    set "quality_mark=[BAD] [BAD]"
    set "quality_tip=距南京约1100km，延迟高"
    goto :identify_done
)

:identify_done

:: ============================================================
:: 输出质量报告
:: ============================================================
echo ==============================================
echo  服务器质量报告
echo ==============================================
echo.
echo  服务器IP    : %server_ip%
echo  节点名称    : %server_type%
echo  所在位置    : %server_location%
echo  承载大区    : %server_games%
echo  ICMP延迟    : %ping_delay%
if "%ping_ok%"=="1" (
    echo  游戏内估算  : %ping_delay% %ingame_offset%
) else (
    echo  游戏内估算  : 无法估算（ping被屏蔽，游戏连接正常）
)
echo  质量评级    : %quality_mark%
echo  评级说明    : %quality_tip%
echo.

if not "%server_region%"=="Nanjing" (
    if not "%server_region%"=="Unknown" (
        echo -----------------------------------------------
        echo  [提示] 当前连接的是%server_region%节点
        echo         南京电信用户建议优先选择南京本地大区
        echo -----------------------------------------------
        echo.
    )
)

echo ==============================================
echo  南京电信用户最优服务器排序
echo ==============================================
echo.
echo  1. [BEST] 南京二长核心节点
echo            IP : 180.102.58.x / 180.102.59.x
echo            区 : 皮尔特沃夫 均衡教派 影流 守望之海
echo            延迟 = ICMP + 3~5ms
echo.
echo  2. [OK] 南京扩容边缘节点
echo            IP : 114.221.151.x / 114.221.152.x
echo            区 : 艾欧尼亚（高峰期扩容）
echo            延迟 = ICMP + 15~20ms
echo.
echo  3. [OK] Shanghai Telecom Primary
echo            IP : 180.163.x.x / 140.206.x.x
echo            区 : Ionia, Zaun
echo            延迟 = ICMP + 8~12ms
echo.
echo  4. [BAD]   Guangdong/西南/华北节点
echo            距南京1000km+，不建议南京用户使用
echo.
echo ==============================================
echo.
echo  重要：不要使用任何游戏加速器
echo  同城同运营商是最低延迟的最优解
echo  加速器引入额外中转，只会让延迟更高
echo.
echo 按任意键退出...
pause >nul
exit /b 0
