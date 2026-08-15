# -*- coding: utf-8 -*-
# 需管理员权限执行（由 admin_fix.cmd 以 UAC 提权调用）
# 1) NewsWriterDaily 任务改为隐藏窗口执行
# 2) 防火墙放行 8123 端口（仪表盘手机访问）
$ErrorActionPreference = "Continue"
$log = Join-Path $env:TEMP "nw_admin_fix.log"
$tools = Split-Path -Parent $PSScriptRoot
$ps1 = Join-Path $tools "schedule\run_daily.ps1"

Add-Content -Path $log -Value ("[{0}] === admin fix start ===" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

$tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
$out = schtasks /change /tn "NewsWriterDaily" /tr $tr 2>&1
Add-Content -Path $log -Value ("[1] schtasks /change -> " + ($out -join " | ")) -Encoding UTF8

$q = schtasks /query /tn "NewsWriterDaily" /xml 2>&1
Add-Content -Path $log -Value ("[2] Daily XML Hidden line -> " + ((($q | Select-String -Pattern '<Hidden>|run_daily.ps1').Line.Trim()) -join " / ")) -Encoding UTF8

$fw = netsh advfirewall firewall add rule name="NewsWriterDashboard" dir=in action=allow protocol=TCP localport=8123 2>&1
Add-Content -Path $log -Value ("[3] firewall -> " + ($fw -join " | ")) -Encoding UTF8

$ua = netsh http add urlacl url=http://*:8123/ user=Everyone 2>&1
Add-Content -Path $log -Value ("[4] urlacl -> " + ($ua -join " | ")) -Encoding UTF8

Add-Content -Path $log -Value ("[{0}] === admin fix done ===" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host "已完成，详情见 $log" -ForegroundColor Green
Write-Host "按任意键关闭..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
