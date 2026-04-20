@echo off
setlocal

set "CANONICAL_UPDATER=%~dp0trade_mode\auto-update.bat"
if not exist "%CANONICAL_UPDATER%" (
  echo Could not find "%CANONICAL_UPDATER%".
  echo Reinstall the mod from the latest release zip.
  exit /b 1
)

call "%CANONICAL_UPDATER%" %*
exit /b %ERRORLEVEL%
