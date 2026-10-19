@echo off
setlocal
if "%VCBS_ROOT%"=="" (
  if exist "%~dp0..\..\..\..\..\vibe-coding-Bootstrap\bootstrap" (
    set "VCBS_ROOT=%~dp0..\..\..\..\..\vibe-coding-Bootstrap"
  )
)
if "%VCBS_ROOT%"=="" (
  echo Error: VCBS_ROOT is not set or does not point to a valid vibe-coding-Bootstrap checkout. >&2
  echo Please set VCBS_ROOT to your trusted vibe-coding-Bootstrap repository path: >&2
  echo   set VCBS_ROOT=C:\path\to\vibe-coding-Bootstrap >&2
  exit /b 1
)
if not exist "%VCBS_ROOT%\bootstrap" (
  echo Error: VCBS_ROOT is not set or does not point to a valid vibe-coding-Bootstrap checkout. >&2
  echo Please set VCBS_ROOT to your trusted vibe-coding-Bootstrap repository path: >&2
  echo   set VCBS_ROOT=C:\path\to\vibe-coding-Bootstrap >&2
  exit /b 1
)
if "%PYTHON%"=="" set "PYTHON=python"
set "PYTHONPATH=%VCBS_ROOT%;%PYTHONPATH%"
"%PYTHON%" -m bootstrap %*
exit /b %ERRORLEVEL%
