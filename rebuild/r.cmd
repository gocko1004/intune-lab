@echo off
rem Launcher pushed into the guest's System32 folder, which is already on PATH.
rem Typing "r" at any prompt finds it, so no path and no backslash are needed.
rem The awkward characters live in this file instead of in what you type.
powershell -ExecutionPolicy Bypass -File C:\h.ps1
pause
