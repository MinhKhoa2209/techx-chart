$ErrorActionPreference = 'Stop'

foreach ($path in @('.gitignore', 'LICENSE', 'README.md')) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required bootstrap file: $path"
  }
}

$phase9Script = Join-Path $PSScriptRoot 'phase9-aws-acceptance.ps1'
if (-not (Test-Path -LiteralPath $phase9Script)) {
  throw 'Missing Phase 9 AWS acceptance script.'
}

& (Join-Path $PSScriptRoot 'test-chart.ps1')

$forbidden = git ls-files | Select-String -Pattern '(^|/)(\.env$|rendered/)|\.(tfstate|tfplan)$'
if ($forbidden) {
  throw "Forbidden generated or sensitive path is tracked: $($forbidden -join ', ')"
}

Write-Host 'techx-chart verification passed.'
