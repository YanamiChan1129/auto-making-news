@echo off
rem 以管理员身份修复：1) 每日任务隐藏窗口 2) 防火墙放行 8123 端口
rem 提示 UAC 时请点"是"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\bocchi\Desktop\openwork\tools\schedule\admin_fix.ps1'"
