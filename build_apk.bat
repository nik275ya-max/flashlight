@echo off
cd /d C:\project\flashlight
call C:\flutter\bin\flutter.bat build apk --release > C:\project\flashlight\build_out.txt 2>&1
echo EXIT=%ERRORLEVEL% >> C:\project\flashlight\build_out.txt
