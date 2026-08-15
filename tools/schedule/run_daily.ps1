# -*- coding: utf-8 -*-
param([switch]$Rerun)
$ErrorActionPreference = "Continue"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tools = Split-Path -Parent $PSScriptRoot

$ts = Get-Date -Format "yyyy-MM-dd"
$log = Join-Path $env:TEMP "news_writer_$ts.log"
$stdout = Join-Path $env:TEMP "news_writer_$ts.out.tmp"
$stderr = Join-Path $env:TEMP "news_writer_$ts.err.tmp"
$TIMEOUT_MIN = 180
$startTime = Get-Date

$progressDir = Join-Path $tools "state\progress"
$null = New-Item -ItemType Directory -Path $progressDir -Force
$progressFile = Join-Path $progressDir "$ts.json"
$stepsFile = Join-Path $progressDir "steps_$ts.txt"

$outCount = 0
$errCount = 0

function Write-Log($msg) {
    Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -Encoding UTF8
}

# 启动仪表盘服务（若端口未监听）
function Ensure-Server {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $tcp.Connect("127.0.0.1", 8123)
        $tcp.Close()
        return
    } catch { }
    $serve = Join-Path $tools "dashboard\serve.ps1"
    Start-Process powershell -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $serve) -WindowStyle Hidden | Out-Null
    Write-Log "dashboard server started on http://127.0.0.1:8123"
}

# 主运行开始时在默认浏览器弹出仪表盘
function Open-Dashboard {
    Start-Process "http://127.0.0.1:8123/"
    Write-Log "opened dashboard in default browser"
}

# 把 out/err 的增量行合并进主日志（实时 tail）
function Merge-Tail {
    foreach ($pair in @(@($stdout, [ref]$outCount), @($stderr, [ref]$errCount))) {
        $f = $pair[0]
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $lines = @(Get-Content -LiteralPath $f -Encoding UTF8)
        $prev = $pair[1].Value
        if ($lines.Count -gt $prev) {
            for ($i = $prev; $i -lt $lines.Count; $i++) {
                Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $lines[$i]) -Encoding UTF8
            }
            $pair[1].Value = $lines.Count
        }
    }
}

function Detect-Phase {
    $tail = @(Get-Content -LiteralPath $log -Tail 80 -ErrorAction SilentlyContinue)
    $all = $tail -join "`n"
    if ($all -match "done \(exit 0\)") { return "done" }
    if ($all -match "TIMEOUT") { return "timeout" }
    if ($all -match "INCOMPLETE") { return "failed" }
    if ($all -match "rerun mode") { return "rerun" }
    if ($all -match "skip:") { return "skip" }
    if ($all -match "written_topics|save_daily_news|refresh_window") { return "archive" }
    if ($all -match "verify_docx") { return "verify" }
    if ($all -match "build_docx") { return "build" }
    if ($all -match "fetch_image|WebFetch|Exa Web Search") { return "image" }
    if ($all -match "websearch|Web Search|find_news") { return "search" }
    if ($all -match "starting news-writer") { return "start" }
    return "running"
}

function Get-ArticleStatuses {
    $arts = @()
    for ($i = 1; $i -le 10; $i++) {
        $a = @{ no = $i; title = ""; status = "待写" }
        if (Test-Path -LiteralPath $stepsFile) {
            $titleLine = @(Select-String -LiteralPath $stepsFile -Pattern "^article $($i): " | Select-Object -Last 1)
            $done = @(Select-String -LiteralPath $stepsFile -Pattern "^article $($i) done$" -Quiet)
            if ($titleLine.Count -gt 0) {
                $a.title = ($titleLine[0].Line -replace "^article $($i): ", "")
                $a.status = if ($done) { "已完成" } else { "写作中" }
            } elseif ($done) {
                $a.status = "已完成"
            }
        }
        $arts += $a
    }
    return $arts
}

function Update-Progress([string]$status) {
    $todayDir = Join-Path $root (Join-Path "article" $ts)
    $docx = @(Get-ChildItem -LiteralPath $todayDir -Filter "*.docx" -ErrorAction SilentlyContinue)
    $tmpImages = Join-Path $tools "scripts\tmp_images"
    $imgs = @(Get-ChildItem -LiteralPath $tmpImages -Filter "*.jpg" -ErrorAction SilentlyContinue)
    $running = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match "opencode" -and $_.CommandLine -match "run --agent news-writer" -and $_.CommandLine -notmatch "aidesktop"
    }
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    $eta = $null
    if ($status -eq "running") {
        if ($docx.Count -gt 0) {
            $eta = [math]::Ceiling($elapsed / $docx.Count * (10 - $docx.Count))
        } else {
            $eta = [math]::Max(1, 50 - $elapsed)
        }
    } elseif ($status -eq "done") {
        $eta = 0
    }
    $prog = [ordered]@{
        date         = $ts
        status       = $status
        phase        = (Detect-Phase)
        started_at   = $startTime.ToString("HH:mm:ss")
        elapsed_min  = $elapsed
        eta_min      = $eta
        docx_done    = $docx.Count
        images_found = $imgs.Count
        agent_alive  = [bool]$running
        articles     = @(Get-ArticleStatuses)
        log_tail     = @(Get-Content -LiteralPath $log -Tail 40 -ErrorAction SilentlyContinue)
        last_update  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $prog | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $progressFile -Encoding UTF8
    # 清理 7 天前的进度文件
    Get-ChildItem -LiteralPath $progressDir -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue
}

Ensure-Server

# S4: 当天是否已产出 docx，避免补跑/重跑（S3 catch-up 配合）
$todayDir = Join-Path $root (Join-Path "article" $ts)
$existing = @(Get-ChildItem -Path $todayDir -Filter "*.docx" -ErrorAction SilentlyContinue)
if ($Rerun) {
    $existing | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "rerun mode: cleared $($existing.Count) existing docx, rewriting today"
} elseif ($existing.Count -ge 10) {
    Write-Log "skip: $todayDir already has $($existing.Count) docx, task already done"
    Update-Progress "skip"
    exit 0
}

Open-Dashboard

Write-Log "starting news-writer task (timeout ${TIMEOUT_MIN}min)"
Update-Progress "running"

# opencode 可执行文件路径：优先环境变量 OPENCODE_CMD，否则依赖 PATH
$opencode = if ($env:OPENCODE_CMD) { $env:OPENCODE_CMD } else { "opencode.cmd" }
$procArgs = @("run", "--agent", "news-writer", "--auto", "Start today's news writing task")

# 必须在 tools 目录下运行，opencode 才能找到 tools\.opencode\agent\news-writer.md
Set-Location $tools

$p = Start-Process -FilePath $opencode -ArgumentList $procArgs -NoNewWindow `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

# 等待循环：opencode.cmd 是 cmd 包装，其句柄可能先于真正的 opencode.exe 退出，
# 因此不依赖 $p.HasExited，而是检测实际运行的 news-writer opencode 进程是否仍存活。
$deadline = (Get-Date).AddMinutes($TIMEOUT_MIN)
$exited = $false
while ((Get-Date) -lt $deadline) {
    Merge-Tail
    Update-Progress "running"
    $running = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match "opencode" -and
        $_.CommandLine -match "run --agent news-writer" -and
        $_.CommandLine -notmatch "aidesktop"
    }
    if (-not $running) {
        $exited = $true
        break
    }
    Start-Sleep -Seconds 10
}

Merge-Tail

if (-not $exited) {
    Write-Log "TIMEOUT after ${TIMEOUT_MIN}min, killing process tree"
    $victims = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match "opencode" -and
        $_.CommandLine -match "run --agent news-writer" -and
        $_.CommandLine -notmatch "aidesktop"
    }
    foreach ($v in $victims) {
        try { Stop-Process -Id $v.ProcessId -Force -ErrorAction Stop } catch { Write-Log "Stop-Process failed: $_" }
        taskkill /PID $v.ProcessId /T /F 2>$null | Out-Null
    }
    Update-Progress "timeout"
    & (Join-Path $PSScriptRoot "toast.ps1") -Title "新闻写作超时" -Message "任务运行超过 ${TIMEOUT_MIN} 分钟已被终止，请在仪表盘查看详情" -Level error
    exit 1
}

$tmpImages = Join-Path $tools "scripts\tmp_images"
if (Test-Path $tmpImages) {
    Remove-Item (Join-Path $tmpImages "*") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "cleaned tmp_images intermediate files"
}

# S5: 退出前校验交付完整性：10 篇 docx + 素材存档（json 与 md）必须齐全
$final = @(Get-ChildItem -Path $todayDir -Filter "*.docx" -ErrorAction SilentlyContinue)
if ($final.Count -lt 10) {
    # 兼容：agent 偶发用相对路径写到 tools\article\ 下，自动搬回根目录
    $altDir = Join-Path $tools (Join-Path "article" $ts)
    $alt = @(Get-ChildItem -LiteralPath $altDir -Filter "*.docx" -ErrorAction SilentlyContinue)
    if ($alt.Count -ge 10) {
        $null = New-Item -ItemType Directory -Path $todayDir -Force
        Move-Item (Join-Path $altDir "*.docx") -Destination $todayDir -Force
        Write-Log "moved $($alt.Count) docx from tools\article to article (relative-path fix)"
        Remove-Item $altDir -Recurse -Force -ErrorAction SilentlyContinue
        $final = @(Get-ChildItem -Path $todayDir -Filter "*.docx" -ErrorAction SilentlyContinue)
    }
}
$dailyState = Join-Path $tools "state\daily_news"
$dailyJson = Join-Path $dailyState "$ts.json"
$dailyMd = Join-Path $dailyState "$ts.md"

# 失败时自动补跑一次（仅首次运行，-Rerun 模式不再触发，防止循环）
function Schedule-AutoRetry {
    if ($Rerun) { return }
    $retryFlag = Join-Path $env:TEMP "news_writer_${ts}.retry"
    if (Test-Path $retryFlag) { return }
    Set-Content -LiteralPath $retryFlag -Value "1" -Encoding UTF8
    $retryLog = Join-Path $env:TEMP "news_writer_${ts}_retry.log"
    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
        "Start-Sleep -Seconds 300; & '$PSScriptRoot\run_daily.ps1' -Rerun *>> '$retryLog' 2>&1"
    ) | Out-Null
    Write-Log "auto-retry scheduled: rerun in 5 minutes (once)"
    & (Join-Path $PSScriptRoot "toast.ps1") -Title "新闻写作失败，将自动补跑" -Message "5 分钟后自动重跑一次，请留意通知" -Level warn
}

if ($final.Count -lt 10) {
    Write-Log "INCOMPLETE: only $($final.Count)/10 docx produced"
    Update-Progress "failed"
    Schedule-AutoRetry
    & (Join-Path $PSScriptRoot "toast.ps1") -Title "新闻写作失败" -Message "今日仅产出 $($final.Count)/10 篇，请在仪表盘查看详情" -Level error
    exit 1
}
if (-not (Test-Path $dailyJson)) {
    Write-Log "INCOMPLETE: archive json missing ($dailyJson)"
    Update-Progress "failed"
    Schedule-AutoRetry
    & (Join-Path $PSScriptRoot "toast.ps1") -Title "新闻写作失败" -Message "素材存档缺失（json），任务未完成" -Level error
    exit 1
}
if (-not (Test-Path $dailyMd)) {
    Write-Log "INCOMPLETE: archive md missing ($dailyMd)"
    Update-Progress "failed"
    Schedule-AutoRetry
    & (Join-Path $PSScriptRoot "toast.ps1") -Title "新闻写作失败" -Message "素材存档缺失（md），任务未完成" -Level error
    exit 1
}

Write-Log "done (exit 0)"
Update-Progress "done"
& (Join-Path $PSScriptRoot "toast.ps1") -Title "今日新闻写作完成" -Message "已生成 $($final.Count) 篇：$($final.Name -join '、')" -Level success
exit 0
