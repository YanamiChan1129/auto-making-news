@echo off
rem 每日备份（NewsWriterBackup 任务调用，每天 05:45）: article + state 镜像到 openwork\_backup
set "ROOT=C:\Users\bocchi\Desktop\openwork"
set "DST=%ROOT%\_backup"
if not exist "%DST%" mkdir "%DST%"
robocopy "%ROOT%\article" "%DST%\article" /MIR /R:1 /W:1 /NDL /NFL >> "%TEMP%\news_writer_backup.log"
robocopy "%ROOT%\tools\state" "%DST%\state" /MIR /R:1 /W:1 /NDL /NFL >> "%TEMP%\news_writer_backup.log"
echo [%date% %time%] backup done >> "%TEMP%\news_writer_backup.log"
