param(
  [string]$GameRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "factorio-game"),
  [int]$UntilTick = 700
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot "build-mod.ps1"
$factorioExe = Join-Path $GameRoot "bin\x64\factorio.exe"
$modsRoot = Join-Path $GameRoot "mods"
$savesRoot = Join-Path $GameRoot "saves"
$configDir = Join-Path $GameRoot "config"
$configPath = Join-Path $configDir "config.ini"
$scenarioName = "factorio-trade-mode/trade-tests"
$reportPrefix = "TRADE_MODE_TEST_REPORT "

if (-not (Test-Path -LiteralPath $factorioExe)) {
  throw "Factorio executable not found: $factorioExe"
}

if (-not (Test-Path -LiteralPath $configPath)) {
  New-Item -ItemType Directory -Force -Path $configDir | Out-Null
  Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @"
[path]
read-data=__PATH__executable__/../../data
write-data=__PATH__executable__/../..
"@
}

New-Item -ItemType Directory -Force -Path $modsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $savesRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $GameRoot "scenarios") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $GameRoot "archive") | Out-Null

function Get-SavePaths {
  if (-not (Test-Path -LiteralPath $savesRoot)) {
    return @()
  }

  return @(Get-ChildItem -LiteralPath $savesRoot -Recurse -Filter *.zip -File | Select-Object -ExpandProperty FullName)
}

function Invoke-FactorioCapture {
  param(
    [string[]]$Arguments,
    [string]$Description
  )

  $output = & $factorioExe @Arguments 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE.`n$output"
  }
  return $output
}

function Get-LatestGeneratedSave {
  param(
    [datetime]$StartTime,
    [string[]]$ExistingPaths
  )

  $existingLookup = @{}
  foreach ($path in $ExistingPaths) {
    $existingLookup[$path] = $true
  }

  $candidates = Get-ChildItem -LiteralPath $savesRoot -Recurse -Filter *.zip -File | Where-Object {
    $_.LastWriteTime -ge $StartTime -or -not $existingLookup.ContainsKey($_.FullName)
  } | Sort-Object LastWriteTime -Descending

  return $candidates | Select-Object -First 1
}

function Parse-ReportFromOutput {
  param(
    [string]$Output
  )

  $lines = $Output -split "`r?`n"
  $reportLine = $lines | Where-Object { $_ -like "*$reportPrefix*" } | Select-Object -Last 1
  if (-not $reportLine) {
    throw "Factorio output did not contain a structured test report line.`n$Output"
  }

  $markerIndex = $reportLine.IndexOf($reportPrefix)
  if ($markerIndex -lt 0) {
    throw "Structured report marker was not found in the selected report line."
  }

  $jsonText = $reportLine.Substring($markerIndex + $reportPrefix.Length).Trim()
  if (-not $jsonText) {
    throw "Structured report line did not contain JSON payload."
  }

  return $jsonText | ConvertFrom-Json
}

& $buildScript -GameRoot $GameRoot | Out-Host

$existingSaves = Get-SavePaths
$scenarioConversionStart = Get-Date
Invoke-FactorioCapture -Description "scenario conversion" -Arguments @(
  "--mod-directory",
  $modsRoot,
  "--scenario2map",
  $scenarioName,
  "--disable-audio"
) | Out-Host

$generatedSave = Get-LatestGeneratedSave -StartTime $scenarioConversionStart -ExistingPaths $existingSaves
if (-not $generatedSave) {
  throw "Scenario conversion did not produce a save in $savesRoot."
}

$runOutput = Invoke-FactorioCapture -Description "bounded save run" -Arguments @(
  "--mod-directory",
  $modsRoot,
  "--load-game",
  $generatedSave.FullName,
  "--until-tick",
  $UntilTick.ToString(),
  "--disable-audio"
)
$runOutput | Out-Host

$report = Parse-ReportFromOutput -Output $runOutput
$passed = [int]$report.summary.passed
$failed = [int]$report.summary.failed

Write-Output ("Scenario report: passed={0} failed={1}" -f $passed, $failed)
if ($failed -gt 0) {
  $report.scenarios | Where-Object { -not $_.ok } | ForEach-Object {
    Write-Output ("FAILED {0}: {1}" -f $_.name, ($_.details | ConvertTo-Json -Depth 6 -Compress))
  }
  throw "Factorio scenario suite reported failures."
}
