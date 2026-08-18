# -*- coding: utf-8 -*-
param([switch]$Rerun, [switch]$Topup, [switch]$Attach)
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
    # 只扫描本次运行（最后一次实例分隔行之后）最近 40 行，逐行取"最后命中的阶段"，
    # 避免历史/计划性文本（如提到脚本名）把阶段永久锁定或抢占显示
    $raw = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
    $marker = ""
    for ($i = $raw.Count - 1; $i -ge 0; $i--) {
        if ($raw[$i] -match "===== run start") {
            $marker = $raw[$i]
            break
        }
    }
    $tail = if ($marker) {
        @($raw | Select-Object -Skip $i | Select-Object -Last 40)
    } else {
        @($raw | Select-Object -Last 40)
    }
    $patterns = [ordered]@{
        done    = 'done \(exit 0\)'
        timeout = 'TIMEOUT after \d+min'
        failed  = 'INCOMPLETE: only'
        rerun   = 'rerun mode'
        topup   = 'topup mode'
        skip    = 'skip: .*already has'
        archive = '\$ python scripts\\(save_daily_news|refresh_window)'
        verify  = '\$ python scripts\\verify_docx'
        build   = '\$ python scripts\\build_docx'
        image   = 'fetch_image|WebFetch'
        search  = 'websearch|Web Search|find_news'
        start   = 'starting news-writer'
    }
    $phase = "running"
    foreach ($line in $tail) {
        foreach ($k in $patterns.Keys) {
            if ($line -match $patterns[$k]) { $phase = $k }
        }
    }
    return $phase
}

function Get-ArticleStatuses {
    # 兜底标题：steps 缺失时从当天素材存档按顺序取
    $fallback = @()
    $dailyJson = Join-Path $tools "state\daily_news\$ts.json"
    if (Test-Path -LiteralPath $dailyJson) {
        try {
            $daily = Get-Content -LiteralPath $dailyJson -Raw -Encoding UTF8 | ConvertFrom-Json
            $fallback = @($daily.items | ForEach-Object { $_.title })
        } catch { }
    }
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
        if (-not $a.title -and $i -le $fallback.Count -and $fallback[$i - 1]) {
            $a.title = $fallback[$i - 1]
        }
        $arts += $a
    }
    return $arts
}

function Get-AgentProcesses {
    # 双轨检测：高权限进程的 CommandLine 可能读不到（为空），此时按进程名精确匹配；
    # -ceq 区分 CLI 的 opencode.exe 与桌面版的 OpenCode.exe（大小写敏感）
    Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -ceq "opencode.exe") -or
        ($_.CommandLine -match "opencode" -and $_.CommandLine -match "run --agent news-writer" -and $_.CommandLine -notmatch "aidesktop")
    }
}

function Update-Progress([string]$status) {
    $todayDir = Join-Path $root (Join-Path "article" $ts)
    $docx = @(Get-ChildItem -LiteralPath $todayDir -Filter "*.docx" -ErrorAction SilentlyContinue)
    $tmpImages = Join-Path $tools "scripts\tmp_images"
    $imgs = @(Get-ChildItem -LiteralPath $tmpImages -Filter "*.jpg" -ErrorAction SilentlyContinue)
    $running = Get-AgentProcesses
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
log_tail     = @(Get-Content -LiteralPath $log -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
        last_update  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $json = ($prog | ConvertTo-Json -Depth 4) -replace "\r\n", "`n"
    [System.IO.File]::WriteAllText($progressFile, $json, (New-Object System.Text.UTF8Encoding($false)))
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
} elseif ($Topup) {
    Write-Log "topup mode: keeping $($existing.Count) existing docx, writing the rest to reach 10"
    if ($existing.Count -ge 10) {
        Write-Log "skip: already has $($existing.Count) docx, nothing to top up"
        Update-Progress "skip"
        exit 0
    }
    if ($existing.Count -eq 0) {
        Write-Log "topup mode with 0 existing docx, falling back to full run"
    }
} elseif ($existing.Count -ge 10) {
    Write-Log "skip: $todayDir already has $($existing.Count) docx, task already done"
    Update-Progress "skip"
    exit 0
}

if (-not $Attach) { Open-Dashboard }

# attach 接管前先恢复原实例的开始时间（必须在 Update-Progress 之前，否则读到的是自己刚写入的值）
if ($Attach -and (Test-Path -LiteralPath $progressFile)) {
    try {
        $old = Get-Content -LiteralPath $progressFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($old.started_at -match "^\d{2}:\d{2}:\d{2}$") {
            $script:startTime = [datetime]::ParseExact((Get-Date -Format "yyyy-MM-dd ") + $old.started_at, "yyyy-MM-dd HH:mm:ss", $null)
            Write-Log "attach mode: resumed startTime from progress ($($old.started_at))"
        } else {
            Write-Log "attach mode: progress started_at unrecognized ($($old.started_at)), keeping current"
        }
    } catch {
        Write-Log "attach mode: failed to resume startTime: $_"
    }
}

$mode = if ($Rerun) { "rerun" } elseif ($Topup) { "topup" } elseif ($Attach) { "attach" } else { "full" }
Write-Log "===== run start <$(Get-Date -Format 'HH:mm:ss')> mode=$mode docx_existing=$($existing.Count) ====="
Write-Log "starting news-writer task (timeout ${TIMEOUT_MIN}min)"
Update-Progress "running"

# opencode 可执行文件路径：优先环境变量 OPENCODE_CMD，否则依赖 PATH
$opencode = if ($env:OPENCODE_CMD) { $env:OPENCODE_CMD } else { "opencode.cmd" }
$prompt = if ($Topup) {
    "Continue today's news writing task: KEEP the $($existing.Count) existing articles, write the missing articles (article no. $($existing.Count+1) to 10) to reach 10 total today, then update the archive to 10 items"
} else {
    "Start today's news writing task"
}
$procArgs = @("run", "--agent", "news-writer", "--auto", $prompt)

# 必须在 tools 目录下运行，opencode 才能找到 tools\.opencode\agent\news-writer.md
Set-Location $tools

# 用 cmd /c 内部重定向（字节流原样写入、不转码），agent 的 UTF-8 中文输出才能原样落盘，
# 避免 PS 重定向按 GBK 误读导致日志乱码（Merge-Tail 按 UTF-8 读回）
$cmdLine = '/c ""' + $opencode + '" run --agent news-writer --auto "' + $prompt + '" 1> "' + $stdout + '" 2> "' + $stderr + '""'
Write-Log "agent cmdline: $cmdLine"
if ($Attach) {
    Write-Log "attach mode: reusing existing agent (pid $($(Get-AgentProcesses).ProcessId -join ','))"
    # attach 不重复输出 agent 已产生的内容（旧实例已合并的归它管）
    if (Test-Path -LiteralPath $stdout) { $script:outCount = @(Get-Content -LiteralPath $stdout).Count }
    if (Test-Path -LiteralPath $stderr) { $script:errCount = @(Get-Content -LiteralPath $stderr).Count }
} else {
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdLine -NoNewWindow -PassThru
}

# 等待循环：opencode.cmd 是 cmd 包装，其句柄可能先于真正的 opencode.exe 退出，
# 因此不依赖 $p.HasExited，而是检测实际运行的 news-writer opencode 进程是否仍存活。
$deadline = (Get-Date).AddMinutes($TIMEOUT_MIN)
$exited = $false
while ((Get-Date) -lt $deadline) {
    Merge-Tail
    Update-Progress "running"
    $running = Get-AgentProcesses
    if (-not $running) {
        $exited = $true
        break
    }
    Start-Sleep -Seconds 10
}

Merge-Tail

if (-not $exited) {
    Write-Log "TIMEOUT after ${TIMEOUT_MIN}min, killing process tree"
    $victims = Get-AgentProcesses
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

# 失败时自动补跑一次（仅首次运行且非补足模式，防止覆盖已有成果）
function Schedule-AutoRetry {
    if ($Rerun -or $Topup -or $Attach) { return }
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

