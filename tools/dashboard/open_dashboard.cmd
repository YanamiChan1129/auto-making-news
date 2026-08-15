@echo off
rem 打开新闻写作仪表盘：服务未启动则先拉起，再打开浏览器
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$t = New-Object System.Net.Sockets.TcpClient; try { $t.Connect('127.0.0.1', 8123); $t.Close() } catch { Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\bocchi\Desktop\openwork\tools\dashboard\serve.ps1'; Start-Sleep -Seconds 2 }"
start "" http://127.0.0.1:8123/
