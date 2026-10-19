@echo off
cd /d C:\project\flashlight
set PATH=C:\Windows\System32\WindowsPowerShell\v1.0;%PATH%
call C:\flutter\bin\flutter.bat build apk --release > C:\project\flashlight\build_out.txt 2>&1
echo EXIT=%ERRORLEVEL% >> C:\project\flashlight\build_out.txt
