@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0KDEConnect-ContextMenu.ps1"
if errorlevel 1 >>"%~dp0KDEConnect-ContextMenu.log" echo [%date% %time%] Script exited with code %errorlevel%
