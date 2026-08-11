$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$evidencePath = Join-Path $root 'evidence/demo/README.md'

if (-not (Test-Path -LiteralPath $evidencePath)) {
  throw 'Missing sanitized demo evidence README.'
}

$forbiddenPaths = git ls-files | Select-String -Pattern '(^|/)(\.env$|kubeconfig|rendered/|\.terraform/|\.plans/)|\.(tfstate|tfplan|pem|key)$'
if ($forbiddenPaths) {
  throw "Sensitive/generated path is tracked: $($forbiddenPaths -join ', ')"
}

$evidence = Get-Content -Raw -LiteralPath $evidencePath
foreach ($heading in @(
  '## Phase 7 immutable artifacts',
  '## Phase 8 GitOps and public acceptance',
  '## Immediate cost-safe teardown',
  '## Phase 9 local acceptance and current cloud state',
  '## Demo limitations'
)) {
  if (-not $evidence.Contains($heading, [System.StringComparison]::Ordinal)) {
    throw "Evidence is missing required section: $heading"
  }
}

$credentialPatterns = @(
  'AKIA[0-9A-Z]{16}',
  'ASIA[0-9A-Z]{16}',
  '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
  '(?i)aws_secret_access_key\s*[:=]\s*[A-Za-z0-9/+=]{20,}',
  '(?i)authorization\s*[:=]\s*Bearer\s+[A-Za-z0-9._-]{20,}'
)
foreach ($pattern in $credentialPatterns) {
  if ($evidence -match $pattern) { throw "Evidence matches forbidden credential pattern: $pattern" }
}

Write-Host 'Evidence structure, tracked paths, and credential-pattern audit passed.'
