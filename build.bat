@echo off
rem Builds Velocity Heat for Windows and Linux. Double-click, or run: build.bat [all|windows|linux]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
if errorlevel 1 (
	echo.
	echo Build failed. See the messages above.
)
pause
