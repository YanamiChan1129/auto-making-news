@echo off
rem 每周复盘（NewsWriterWeekly 任务调用，每周一 08:00）
python -X utf8 "C:\Users\bocchi\Desktop\openwork\tools\scripts\weekly_report.py" >> "%TEMP%\news_writer_weekly.log" 2>&1
