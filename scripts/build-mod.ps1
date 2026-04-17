param(
  [string]$GameRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "factorio-game")
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$info = Get-Content -Raw (Join-Path $repoRoot "info.json") | ConvertFrom-Json
$modsRoot = Join-Path $GameRoot "mods"
$target = Join-Path $modsRoot ("{0}_{1}" -f $info.name, $info.version)

$excludedNames = @(
  ".git",
  ".github",
  ".npm-cache",
  "factorio-game",
  "node_modules"
)

function Copy-RepoItem {
  param(
    [string]$SourcePath,
    [string]$DestinationPath
  )

  if (Test-Path -LiteralPath $DestinationPath) {
    Remove-Item -LiteralPath $DestinationPath -Recurse -Force
  }

  Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $modsRoot | Out-Null

if (Test-Path -LiteralPath $target) {
  Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $target | Out-Null

Get-ChildItem -LiteralPath $repoRoot -Force | ForEach-Object {
  if ($excludedNames -contains $_.Name) {
    return
  }

  $destination = Join-Path $target $_.Name
  Copy-RepoItem -SourcePath $_.FullName -DestinationPath $destination
}

$modListPath = Join-Path $modsRoot "mod-list.json"
$modList = @{
  mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = $info.name; enabled = $true }
  )
} | ConvertTo-Json -Depth 5
Set-Content -LiteralPath $modListPath -Value $modList -Encoding UTF8

Write-Output ("Built mod to {0}" -f $target)

