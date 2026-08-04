# -*- coding: utf-8 -*-
$ErrorActionPreference = "Continue"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tools = Split-Path -Parent $PSScriptRoot

$ts = Get-Date -Format "yyyy-MM-dd"
$log = Join-Path $env:TEMP "news_writer_$ts.log"
$stdout = Join-Path $env:TEMP "news_writer_$ts.out.tmp"
$stderr = Join-Path $env:TEMP "news_writer_$ts.err.tmp"
$TIMEOUT_MIN = 90

function Write-Log($msg) {
    Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -Encoding UTF8
}

# S4: 当天是否已产出 docx，避免补跑/重跑（S3 catch-up 配合）
$todayDir = Join-Path $root (Join-Path "article" $ts)
$existing = @(Get-ChildItem -Path $todayDir -Filter "*.docx" -ErrorAction SilentlyContinue)
if ($existing.Count -ge 5) {
    Write-Log "skip: $todayDir already has $($existing.Count) docx, task already done"
    exit 0
}

Write-Log "starting news-writer task (timeout ${TIMEOUT_MIN}min)"

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
    exit 1
}

if (Test-Path $stdout) {
    Get-Content $stdout | ForEach-Object { Write-Log $_ }
}
if (Test-Path $stderr) {
    Get-Content $stderr | ForEach-Object { Write-Log "STDERR: $_" }
}
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

$tmpImages = Join-Path $tools "scripts\tmp_images"
if (Test-Path $tmpImages) {
    Remove-Item (Join-Path $tmpImages "*") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "cleaned tmp_images intermediate files"
}

Write-Log "done (exit 0)"
exit 0
