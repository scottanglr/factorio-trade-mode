@echo off
setlocal

set "REPO=scottanglr/factorio-trade-mode"
set "ASSET_PATTERN=factorio-trade-mode_*.zip"
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "TARGET_DIR=%%~fI"

echo Looking for the latest release from %REPO%...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$repo = '%REPO%';" ^
  "$assetPattern = '%ASSET_PATTERN%';" ^
  "$targetDir = [System.IO.Path]::GetFullPath('%TARGET_DIR%');" ^
  "$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('factorio-trade-mode-' + [Guid]::NewGuid().ToString());" ^
  "New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null;" ^
  "try {" ^
  "  $headers = @{ 'User-Agent' = 'factorio-trade-mode-updater' };" ^
  "  $release = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest') -Headers $headers;" ^
  "  $asset = $release.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1;" ^
  "  if (-not $asset) { throw 'No matching release zip was found.' }" ^
  "  $zipPath = Join-Path $tempRoot $asset.name;" ^
  "  $extractDir = Join-Path $tempRoot 'extract';" ^
  "  Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zipPath;" ^
  "  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force;" ^
  "  $packageRoot = Get-ChildItem -Path $extractDir | Select-Object -First 1;" ^
  "  if (-not $packageRoot) { throw 'Release archive was empty.' }" ^
  "  $copyRoot = if ($packageRoot.PSIsContainer) { $packageRoot.FullName } else { $extractDir };" ^
  "  Get-ChildItem -Path $copyRoot -Recurse -File | ForEach-Object {" ^
  "    $relativePath = $_.FullName.Substring($copyRoot.Length).TrimStart('\');" ^
  "    $destinationPath = Join-Path $targetDir $relativePath;" ^
  "    $destinationDir = Split-Path -Path $destinationPath -Parent;" ^
  "    if (-not (Test-Path -Path $destinationDir)) { New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null }" ^
  "    Copy-Item -Path $_.FullName -Destination $destinationPath -Force;" ^
  "  };" ^
  "  Write-Host ('Updated from release ' + $release.tag_name);" ^
  "} finally {" ^
  "  if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }" ^
  "}"

if errorlevel 1 (
  echo Update failed.
  exit /b 1
)

echo Update complete.
exit /b 0
