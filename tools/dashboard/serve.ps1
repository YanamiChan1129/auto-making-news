# -*- coding: utf-8 -*-
# 每日新闻写作仪表盘本地服务：http://127.0.0.1:8123
# 由 run_daily.ps1 或登录任务（NewsWriterDashboard）启动，常驻运行
$ErrorActionPreference = "Continue"

$port = 8123
$tools = Split-Path -Parent $PSScriptRoot
$progressDir = Join-Path $tools "state\progress"
$html = Join-Path $PSScriptRoot "index.html"
$articleRoot = Split-Path -Parent $tools   # 仓库根，含 article\
$selfLog = Join-Path $env:TEMP "news_writer_dashboard.log"

function Log($msg) {
    Add-Content -Path $selfLog -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -Encoding UTF8
}

function Get-LanIp {
    try {
        return (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and $_.PrefixOrigin -ne "WellKnown" } |
            Select-Object -First 1 -ExpandProperty IPAddress)
    } catch { return "" }
}

function Start-Listener([string]$prefix) {
    try {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add($prefix)
        $l.Start()
        return $l
    } catch {
        Log "bind failed: $prefix => $($_.Exception.Message)"
        return $null
    }
}

$listener = Start-Listener "http://*:$port/"
if (-not $listener) {
    $listener = Start-Listener "http://127.0.0.1:$port/"
}
if (-not $listener) {
    Log "start failed (no prefix available)"
    exit 1
}
$lanIp = Get-LanIp
Log "dashboard listening on http://127.0.0.1:$port (LAN: http://$lanIp`:$port)"

function Send-Bytes($ctx, $bytes, $contentType) {
    $ctx.Response.ContentType = $contentType
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Get-DateProg($date) {
    $f = Join-Path $progressDir "$date.json"
    if (Test-Path -LiteralPath $f) {
        return [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    }
    return "null"
}

function Is-ValidDate([string]$date) {
    return $date -match "^20\d\d-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$"
}

# 每个请求在线程池线程独立处理，避免大文件下载阻塞页面轮询
function Handle-Request($ctx) {
    $path = $ctx.Request.Url.AbsolutePath
    try {
        if ($path -eq "/") {
            if (Test-Path -LiteralPath $html) {
                $bytes = [System.IO.File]::ReadAllBytes($html)
                Send-Bytes $ctx $bytes "text/html; charset=utf-8"
            } else {
                $ctx.Response.StatusCode = 404
            }
        } elseif ($path -eq "/api/progress") {
            $date = $ctx.Request.QueryString["date"]
            if (-not $date) { $date = Get-Date -Format "yyyy-MM-dd" }
            if (-not (Is-ValidDate $date)) { $ctx.Response.StatusCode = 400; return }
            $body = Get-DateProg $date
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            Send-Bytes $ctx $bytes "application/json; charset=utf-8"
        } elseif ($path -eq "/api/dates") {
            $dates = @(Get-ChildItem -LiteralPath $progressDir -Filter "*.json" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^20\d\d-\d\d-\d\d\.json$" } |
                Select-Object -ExpandProperty BaseName | Sort-Object -Descending)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($dates | ConvertTo-Json))
            Send-Bytes $ctx $bytes "application/json; charset=utf-8"
        } elseif ($path -eq "/api/ip") {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(('"' + (Get-LanIp) + '"'))
            Send-Bytes $ctx $bytes "application/json; charset=utf-8"
        } elseif ($path -eq "/api/articles") {
            $date = $ctx.Request.QueryString["date"]
            if (-not (Is-ValidDate $date)) { $ctx.Response.StatusCode = 400; return }
            $dir = Join-Path $articleRoot (Join-Path "article" $date)
            $files = @(Get-ChildItem -LiteralPath $dir -Filter "*.docx" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($files | ConvertTo-Json))
            Send-Bytes $ctx $bytes "application/json; charset=utf-8"
        } elseif ($path -like "/article/*") {
            $rel = [System.Uri]::UnescapeDataString($path.Substring("/article/".Length))
            if ($rel -notmatch "^20\d\d-\d\d-\d\d/") { $ctx.Response.StatusCode = 400; return }
            $full = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $articleRoot "article") $rel))
            $allowed = [System.IO.Path]::GetFullPath((Join-Path $articleRoot "article"))
            # 必须严格位于 article\ 目录内（带分隔符边界，防 articleX 兄弟目录穿透）
            $inside = $full.StartsWith($allowed + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
            if ($inside -and (Test-Path -LiteralPath $full)) {
                $bytes = [System.IO.File]::ReadAllBytes($full)
                Send-Bytes $ctx $bytes "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            } else {
                $ctx.Response.StatusCode = 404
            }
        } else {
            $ctx.Response.StatusCode = 404
        }
    } catch {
        Log "request error: $_"
    } finally {
        try { $ctx.Response.Close() } catch {}
    }
}

$n = 0
while ($true) {
    try {
        $ctx = $listener.GetContext()
    } catch {
        Log "getcontext error: $($_.Exception.Message)"
        break
    }
    Handle-Request $ctx
}

Log "dashboard stopped"