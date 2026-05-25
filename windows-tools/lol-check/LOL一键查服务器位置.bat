@echo off
REM ============================================================
REM  IMPORTANT: this batch shell is ASCII-ONLY by design.
REM  cmd parses .bat files in the OEM codepage (GBK on zh-CN
REM  Windows). chcp 65001 only changes console I/O, NOT how
REM  cmd reads the .bat file itself. If we put Chinese here,
REM  GBK misreads the UTF-8 bytes and cmd loses its place,
REM  drifting past `exit /b 0` into the PowerShell section.
REM
REM  All Chinese UI text lives in the PowerShell section below
REM  the ###PS_START### marker. That section is read by
REM  PowerShell as UTF-8 (independent of cmd parsing).
REM ============================================================

REM Capture self path BEFORE chcp 65001 to avoid chinese-path
REM expansion glitches under codepage 65001.
set "BATFILE=%~f0"

chcp 65001 >nul
title LoL Server Check v2
mode con cols=78 lines=32 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $f=[System.IO.File]::ReadAllText($env:BATFILE,[System.Text.Encoding]::UTF8); $m='###'+'PS_START'+'###'; $i=$f.LastIndexOf($m); if($i -lt 0){throw 'PS marker not found in bat file'}; Invoke-Expression $f.Substring($i+$m.Length) } catch { Write-Host ''; Write-Host '=== Bootstrap error ===' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; if($_.ScriptStackTrace){Write-Host ''; Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray}; Write-Host ''; Write-Host 'Press any key to close...' -NoNewline; [void][Console]::ReadKey($true); Write-Host '' }"

REM Belt-and-suspenders: if powershell itself failed to launch
if errorlevel 1 (
  echo.
  echo [Bootstrap] PowerShell exited with errorlevel %errorlevel%.
  echo Press any key to close...
  pause >nul
)

exit /b 0

REM ============================================================
REM  Below: PowerShell section, read by powershell self-read.
REM  cmd never executes past `exit /b 0`, so UTF-8 chinese
REM  bytes below this point are not parsed by cmd at all.
REM ============================================================
###PS_START###

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---------- 配置区 ----------
$Config = @{
    PingCount      = 20      # 游戏中模式 ping 包数
    PreCheckPings  = 10      # 赛前体检每节点 ping 包数
    HttpTimeoutSec = 5
}

# LoL 已知节点字典:沿用原 bat 的 4 条段;每条挑一个代表 IP 用于赛前体检
$LolNodes = @(
    [PSCustomObject]@{
        prefixes = @('180.102.58.', '180.102.59.')
        label    = '南京二长核心节点'
        servers  = '皮尔特沃夫/均衡教派/影流/守望之海'
        expected = '游戏内延迟 ≈ ping + 3-5 ms'
        sampleIp = '180.102.58.100'
    },
    [PSCustomObject]@{
        prefixes = @('114.221.151.', '114.221.152.')
        label    = '南京临时边缘节点'
        servers  = '艾欧尼亚(扩容)'
        expected = '游戏内延迟 ≈ ping + 15-20 ms'
        sampleIp = '114.221.151.100'
    },
    [PSCustomObject]@{
        prefixes = @('180.163.', '140.206.')
        label    = '上海主节点'
        servers  = '艾欧尼亚/祖安'
        expected = '游戏内延迟 ≈ 25-35 ms'
        sampleIp = '180.163.1.100'
    },
    [PSCustomObject]@{
        prefixes = @('113.105.', '119.147.')
        label    = '东莞节点'
        servers  = '黑色玫瑰/诺克萨斯'
        expected = '游戏内延迟 ≈ 40-50 ms'
        sampleIp = '113.105.1.100'
    }
)

# ---------- 网络信息查询 ----------

function Get-MyPublicIPInfo {
    try {
        $r = Invoke-RestMethod -Uri 'http://ip-api.com/json/?lang=zh-CN' `
             -TimeoutSec $Config.HttpTimeoutSec -ErrorAction Stop
        if ($r.status -eq 'success') {
            return [PSCustomObject]@{
                ip      = $r.query
                region  = $r.regionName
                city    = $r.city
                isp     = $r.isp
                source  = 'ip-api.com'
            }
        }
    } catch {}
    try {
        $r = Invoke-RestMethod -Uri 'https://ipinfo.io/json' `
             -TimeoutSec $Config.HttpTimeoutSec -ErrorAction Stop
        return [PSCustomObject]@{
            ip      = $r.ip
            region  = $r.region
            city    = $r.city
            isp     = $r.org
            source  = 'ipinfo.io'
        }
    } catch {}
    return $null
}

function Get-IPGeoInfo {
    param([string]$ip)
    try {
        $r = Invoke-RestMethod -Uri ("http://ip-api.com/json/{0}?lang=zh-CN" -f $ip) `
             -TimeoutSec $Config.HttpTimeoutSec -ErrorAction Stop
        if ($r.status -eq 'success') {
            return [PSCustomObject]@{
                city = ('{0} {1}' -f $r.regionName, $r.city).Trim()
                isp  = $r.isp
            }
        }
    } catch {}
    return $null
}

function Get-LolGameProcesses {
    # 只查游戏主进程。不查 LeagueClient* —— 那是大厅客户端,不连游戏服务器。
    return @(Get-Process -Name 'League of Legends' -ErrorAction SilentlyContinue)
}

function Get-LolPublicIPv4Connections {
    param([int[]]$procIds)
    if (-not $procIds -or $procIds.Count -eq 0) { return @() }
    try {
        return @(Get-NetTCPConnection -State Established -ErrorAction Stop |
            Where-Object { $procIds -contains $_.OwningProcess } |
            Where-Object { $_.RemoteAddress -match '^\d+\.\d+\.\d+\.\d+$' } |
            Where-Object { $_.RemoteAddress -notmatch '^(127\.|10\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' })
    } catch { return @() }
}

function Get-LolServerIP {
    $procs = Get-LolGameProcesses
    if (-not $procs -or $procs.Count -eq 0) { return $null }
    $procIds = @($procs | Select-Object -ExpandProperty Id)
    $conns = Get-LolPublicIPv4Connections -procIds $procIds
    if ($conns.Count -eq 0) { return $null }
    # LoL 游戏进程通常只有一条公网 ipv4 TCP 连接,直接拿第一条
    return ($conns | Select-Object -First 1).RemoteAddress
}

function Show-LolDiagnostic {
    $procs = Get-LolGameProcesses
    if (-not $procs -or $procs.Count -eq 0) {
        Write-Host '   诊断:未检测到 League of Legends 游戏进程' -ForegroundColor DarkGray
        Write-Host '   (本工具不检测 LeagueClient 等大厅客户端,因大厅不连游戏服务器)' -ForegroundColor DarkGray
        return
    }
    Write-Host ('   诊断:发现 {0} 个游戏进程' -f $procs.Count) -ForegroundColor DarkGray
    foreach ($p in $procs) {
        Write-Host ('     - {0} (PID {1})' -f $p.Name, $p.Id) -ForegroundColor DarkGray
    }
    $procIds = @($procs | Select-Object -ExpandProperty Id)
    $conns = Get-LolPublicIPv4Connections -procIds $procIds
    if ($conns.Count -eq 0) {
        Write-Host '   诊断:没有 ipv4 公网 TCP 连接(LoL 可能跑在管理员权限下,请右键 bat → 以管理员身份运行)' -ForegroundColor DarkYellow
    } else {
        Write-Host ('   诊断:发现 {0} 个 ipv4 公网 TCP 连接' -f $conns.Count) -ForegroundColor DarkGray
        foreach ($c in ($conns | Select-Object -First 5)) {
            Write-Host ('     - {0}:{1}' -f $c.RemoteAddress, $c.RemotePort) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

function Resolve-LolServerLabel {
    param([string]$ip)
    foreach ($node in $LolNodes) {
        foreach ($prefix in $node.prefixes) {
            if ($ip.StartsWith($prefix)) { return $node }
        }
    }
    return $null
}

# ---------- 质量测量与评分 ----------

function Measure-Quality {
    param([string]$ip, [int]$count = 20)
    try {
        $results = @(Test-Connection -ComputerName $ip -Count $count -ErrorAction SilentlyContinue)
        $received = @($results | Where-Object { $_.ResponseTime -ne $null -and $_.StatusCode -eq 0 })
        if ($received.Count -eq 0) {
            return [PSCustomObject]@{
                avgMs = 0; minMs = 0; maxMs = 0; jitterMs = 0; lossPct = 100; sampleCount = $count
            }
        }
        $rts = @($received | ForEach-Object { [int]$_.ResponseTime })
        $mean = ($rts | Measure-Object -Average).Average
        $variance = ($rts | ForEach-Object { ($_ - $mean) * ($_ - $mean) } | Measure-Object -Average).Average
        return [PSCustomObject]@{
            avgMs       = [math]::Round($mean, 1)
            minMs       = ($rts | Measure-Object -Minimum).Minimum
            maxMs       = ($rts | Measure-Object -Maximum).Maximum
            jitterMs    = [math]::Round([math]::Sqrt($variance), 1)
            lossPct     = [math]::Round((($count - $received.Count) / $count) * 100, 0)
            sampleCount = $count
        }
    } catch {
        return $null
    }
}

function Get-QualityGrade {
    param($q)
    if ($q.lossPct -eq 0 -and $q.avgMs -le 30 -and $q.jitterMs -le 5) {
        return [PSCustomObject]@{ grade = 'A'; note = '✨ 完美链路' }
    } elseif ($q.lossPct -le 1 -and $q.avgMs -le 50 -and $q.jitterMs -le 10) {
        return [PSCustomObject]@{ grade = 'B'; note = '👍 良好,正常对局无感' }
    } elseif ($q.lossPct -le 3 -and $q.avgMs -le 80) {
        return [PSCustomObject]@{ grade = 'C'; note = '⚠️  可玩但能感到延迟' }
    } else {
        return [PSCustomObject]@{ grade = 'D'; note = '💀 劝退,换时段或排查网络' }
    }
}

function Get-GradeColor {
    param([string]$grade)
    switch ($grade) {
        'A' { 'Green' }
        'B' { 'Cyan' }
        'C' { 'Yellow' }
        'D' { 'Red' }
        default { 'Gray' }
    }
}

# ---------- 日志 ----------

function Write-LogLine {
    param($me, [string]$serverIp, $label, $geo, $q, $grade)
    try {
        $logPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'lol_ping_log.csv'
        if (-not (Test-Path $logPath)) {
            'time,my_ip,my_city,server_ip,node_label,avg_ms,jitter_ms,loss_pct,grade' |
                Out-File -FilePath $logPath -Encoding UTF8
        }
        $nodeLabel = if ($label) { $label.label }
                     elseif ($geo) { "$($geo.city) $($geo.isp)" }
                     else { '未知' }
        $myIp   = if ($me) { $me.ip } else { '' }
        $myCity = if ($me) { $me.city } else { '' }
        $line = '{0},{1},{2},{3},"{4}",{5},{6},{7},{8}' -f `
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            $myIp, $myCity, $serverIp, $nodeLabel,
            $q.avgMs, $q.jitterMs, $q.lossPct, $grade.grade
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
        return $logPath
    } catch {
        return $null
    }
}

# ---------- 报告渲染 ----------

function Show-Header {
    Write-Host ''
    Write-Host '==============================================' -ForegroundColor Cyan
    Write-Host '       英雄联盟服务器一键检测 v2' -ForegroundColor Cyan
    Write-Host '==============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '   只读检测:不修改游戏文件,不注入内存,不触发反作弊' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-MyNetwork {
    param($me)
    Write-Host '📍 你的网络' -ForegroundColor Yellow
    if ($me) {
        Write-Host ('   IP:       {0}' -f $me.ip)
        Write-Host ('   位置:     {0} {1}' -f $me.region, $me.city)
        Write-Host ('   运营商:   {0}' -f $me.isp)
    } else {
        Write-Host '   ⚠️  公网 IP 查询失败(可能没网 / 接口被墙)' -ForegroundColor DarkYellow
    }
    Write-Host ''
}

function Show-InGameReport {
    param([string]$serverIp, $me)

    Write-Host '🎮 游戏服务器' -ForegroundColor Yellow
    $label = Resolve-LolServerLabel -ip $serverIp
    $geo = $null
    if (-not $label) { $geo = Get-IPGeoInfo -ip $serverIp }

    Write-Host ('   IP:       {0}' -f $serverIp)
    if ($label) {
        Write-Host ('   节点:     {0}' -f $label.label) -ForegroundColor Green
        Write-Host ('   服务器:   {0}' -f $label.servers)
        Write-Host ('   预期:     {0}' -f $label.expected)
    } elseif ($geo) {
        Write-Host '   节点:     未知(不在已知 LoL 节点段中)' -ForegroundColor DarkYellow
        Write-Host ('   位置:     {0}' -f $geo.city)
        Write-Host ('   运营商:   {0}' -f $geo.isp)
    } else {
        Write-Host '   节点:     未知,地理查询也失败' -ForegroundColor DarkYellow
    }
    Write-Host ''

    Write-Host ('📊 链路质量 ({0} ICMP packets)' -f $Config.PingCount) -ForegroundColor Yellow
    $q = Measure-Quality -ip $serverIp -count $Config.PingCount
    if (-not $q) {
        Write-Host '   ⚠️  ICMP 测试失败,可能被防火墙拦截' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }
    Write-Host ('   平均:     {0} ms' -f $q.avgMs)
    Write-Host ('   最大:     {0} ms' -f $q.maxMs)
    Write-Host ('   抖动:     {0} ms' -f $q.jitterMs)
    Write-Host ('   丢包率:   {0}%' -f $q.lossPct)
    $g = Get-QualityGrade -q $q
    $color = Get-GradeColor -grade $g.grade
    Write-Host ('   评分:     {0}  {1}' -f $g.grade, $g.note) -ForegroundColor $color
    Write-Host ''

    if ($me) {
        $logPath = Write-LogLine -me $me -serverIp $serverIp -label $label -geo $geo -q $q -grade $g
        if ($logPath) {
            Write-Host ('📝 已记录到 {0}' -f $logPath) -ForegroundColor DarkGray
            Write-Host ''
        }
    }
}

function Show-PreGameCheck {
    Write-Host '🎮 LoL 未连接游戏服务器 — 启动赛前体检模式' -ForegroundColor Yellow
    Write-Host '   (登录大厅 / 英雄选择阶段不会有游戏服务器连接)' -ForegroundColor DarkGray
    Write-Host ''
    Show-LolDiagnostic

    $results = @()
    foreach ($node in $LolNodes) {
        Write-Host ('   测试 {0} ({1}) ...' -f $node.label, $node.sampleIp) -ForegroundColor DarkGray
        $q = Measure-Quality -ip $node.sampleIp -count $Config.PreCheckPings
        if (-not $q) { continue }
        $g = Get-QualityGrade -q $q
        $results += [PSCustomObject]@{
            节点    = $node.label
            服务器  = $node.servers
            平均ms  = $q.avgMs
            jitter  = $q.jitterMs
            '丢包%' = $q.lossPct
            评分    = $g.grade
        }
    }
    Write-Host ''

    if ($results.Count -eq 0) {
        Write-Host '   ⚠️  所有节点都 ping 不通(网络可能完全不通或被全拦)' -ForegroundColor Red
        return
    }

    $sorted = $results | Sort-Object 平均ms
    $sorted | Format-Table -AutoSize | Out-String | Write-Host

    $best = $sorted[0]
    Write-Host ('   ✨ 你到 [{0}] 最稳:平均 {1}ms / 评分 {2}' -f $best.节点, $best.平均ms, $best.评分) `
        -ForegroundColor (Get-GradeColor -grade $best.评分)
    Write-Host '   (赛前 ping 是路由器/边缘 IP,游戏中实际延迟会略高)' -ForegroundColor DarkGray
}

function Show-Footer {
    Write-Host ''
    Write-Host '==============================================' -ForegroundColor Cyan
    Write-Host '💡 同城同运营商不要开加速器,只会增加延迟。' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '按任意键退出...' -NoNewline -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
    Write-Host ''
}

# ---------- 主流程 ----------

function Main {
    Show-Header
    $me = Get-MyPublicIPInfo
    Show-MyNetwork -me $me

    $serverIp = Get-LolServerIP
    if ($serverIp) {
        Show-InGameReport -serverIp $serverIp -me $me
    } else {
        Show-PreGameCheck
    }

    Show-Footer
}

Main
