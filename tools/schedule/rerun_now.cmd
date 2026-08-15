@echo off
rem 手动触发今日新闻写作补跑（隐藏窗口任务）
schtasks /run /tn "NewsWriterRerun"
