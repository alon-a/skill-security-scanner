@echo off
setlocal enabledelayedexpansion

set "BASH_EXE=C:\Program Files\Git\bin\bash.exe"
set "SCRIPT_DIR=%~dp0"
set "URL=%~1"
if "%URL%"=="" set "URL=https://github.com/alon-a/known-bad-skill-fixture"

if not exist "%BASH_EXE%" (
  echo Error: Git Bash not found at "%BASH_EXE%".
  echo Edit BASH_EXE at the top of this file if Git is installed elsewhere.
  exit /b 2
)

where gh >nul 2>&1
if errorlevel 1 (
  echo Error: gh ^(GitHub CLI^) not found on PATH. Install it from https://cli.github.com/
  exit /b 2
)

for /f "delims=" %%T in ('gh auth token 2^>nul') do set "GITHUB_TOKEN=%%T"
if "%GITHUB_TOKEN%"=="" (
  echo Error: could not get a token from "gh auth token". Run "gh auth login" first.
  exit /b 2
)

echo Scanning %URL% ...
if "%~1"=="" (
  "%BASH_EXE%" "%SCRIPT_DIR%scan-github-remote.sh" "%URL%"
) else (
  "%BASH_EXE%" "%SCRIPT_DIR%scan-github-remote.sh" %*
)

exit /b %ERRORLEVEL%
