$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$rendered = Join-Path ([System.IO.Path]::GetTempPath()) "techx-chart-$PID.yaml"
$domainRendered = Join-Path ([System.IO.Path]::GetTempPath()) "techx-chart-domain-$PID.yaml"

try {
  helm lint $root -f (Join-Path $root 'values-demo.yaml')
  if ($LASTEXITCODE -ne 0) { throw 'helm lint failed.' }
  $manifest = helm template techx $root -f (Join-Path $root 'values-demo.yaml')
  if ($LASTEXITCODE -ne 0) { throw 'helm template failed.' }
  $manifest | Set-Content -LiteralPath $rendered -Encoding utf8
  python (Join-Path $root 'tests/assert_manifests.py') $rendered baseline
  if ($LASTEXITCODE -ne 0) { throw 'Manifest assertions failed.' }

  helm lint $root -f (Join-Path $root 'values-demo.yaml') -f (Join-Path $root 'values-domain-vpn.yaml')
  if ($LASTEXITCODE -ne 0) { throw 'domain/VPN helm lint failed.' }
  $domainManifest = helm template techx $root -f (Join-Path $root 'values-demo.yaml') -f (Join-Path $root 'values-domain-vpn.yaml')
  if ($LASTEXITCODE -ne 0) { throw 'domain/VPN helm template failed.' }
  $domainManifest | Set-Content -LiteralPath $domainRendered -Encoding utf8
  python (Join-Path $root 'tests/assert_manifests.py') $domainRendered domainVpn
  if ($LASTEXITCODE -ne 0) { throw 'Domain/VPN manifest assertions failed.' }

  $negativeCases = @(
    @('--set-string', 'workloads.frontend.image.tag=latest'),
    @('--set-string', 'workloads.frontend.image.tag='),
    @('--set-string', 'workloads.catalog-api.port=80'),
    @('--set-string', 'workloads.order-api.resources.limits.memory=invalid')
  )

  foreach ($arguments in $negativeCases) {
    $output = & helm template invalid $root @arguments 2>&1
    if ($LASTEXITCODE -eq 0) {
      throw "Expected schema rejection for: $($arguments -join ' ')"
    }
  }

  Write-Host 'Chart lint, render, schema-negative, manifest, and GitOps tests passed.'
}
finally {
  Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $domainRendered -Force -ErrorAction SilentlyContinue
}
