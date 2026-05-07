@echo off
REM JIRA REST operator - 트래커 → JIRA 일감 생성 큐 처리
REM
REM 1. 자격 증명: operator\.jira_creds.json (gitignored) 또는 env JIRA_USER / JIRA_PASS
REM 2. 더블클릭 또는 cmd 에서 run.bat
REM 3. dry-run: run.bat --dry-run
REM 4. 1건만: run.bat --limit 1
REM
REM 종료 후 창이 닫히지 않도록 마지막에 pause.

setlocal
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] python 이 PATH 에 없습니다. https://www.python.org 설치 후 PATH 등록.
  pause
  exit /b 1
)

python jira_rest_operator.py %*
set RC=%errorlevel%

echo.
if "%RC%"=="0" (
  echo [OK] 처리 완료. 트래커 새로고침으로 result_key / jira_url 백필 확인.
) else (
  echo [FAIL] exit code %RC%. 자격증명/네트워크 확인.
)
echo.
pause
endlocal
