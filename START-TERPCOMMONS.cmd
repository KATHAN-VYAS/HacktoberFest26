@echo off
cd /d "%~dp0"
echo Starting TerpCommons at http://localhost:5173
call npm run dev -- --port 5173
pause
