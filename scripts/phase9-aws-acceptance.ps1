param(
  [ValidateSet('Baseline', 'SelfHeal', 'WaitRevision')]
  [string]$Action = 'Baseline',
  [string]$PublicUrl = '',
  [string]$ExpectedRevision = '',
  [string]$ExpectedImageTag = '',
  [string]$Context = '',
  [string]$Namespace = 'techx-demo',
  [string]$Application = 'techx-demo',
  [int]$TimeoutSeconds = 360
)

$ErrorActionPreference = 'Stop'
$kubectlContext = if ($Context) { @('--context', $Context) } else { @() }

function Invoke-KubectlJson([string[]]$Arguments) {
  $raw = & kubectl @kubectlContext @Arguments -o json
  if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($Arguments -join ' ')" }
  return $raw | ConvertFrom-Json
}

function Get-Application {
  return Invoke-KubectlJson @('-n', 'argocd', 'get', 'application', $Application)
}

function Assert-ArgoHealthy([object]$App) {
  if ($App.status.sync.status -ne 'Synced' -or $App.status.health.status -ne 'Healthy') {
    throw "Argo CD is $($App.status.sync.status)/$($App.status.health.status), expected Synced/Healthy."
  }
}

function Wait-Argo([string]$RevisionPrefix = '') {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $app = Get-Application
    $revisionMatches = -not $RevisionPrefix -or ([string]$app.status.sync.revision).StartsWith($RevisionPrefix)
    if ($app.status.sync.status -eq 'Synced' -and $app.status.health.status -eq 'Healthy' -and $revisionMatches) {
      return $app
    }
    Start-Sleep -Seconds 5
  } while ((Get-Date) -lt $deadline)
  throw "Argo CD did not converge to Synced/Healthy revision '$RevisionPrefix' within $TimeoutSeconds seconds."
}

function Assert-ImageTag([string]$Tag) {
  if (-not $Tag) { return }
  $deployments = Invoke-KubectlJson @('-n', $Namespace, 'get', 'deployments')
  foreach ($deployment in $deployments.items) {
    $images = @($deployment.spec.template.spec.containers.image)
    if ($images.Count -ne 1 -or $images[0] -notmatch ":$([regex]::Escape($Tag))$") {
      throw "$($deployment.metadata.name) does not run expected immutable tag $Tag."
    }
  }
}

if ($Action -eq 'Baseline') {
  if (-not $PublicUrl.StartsWith('http://')) {
    throw 'Baseline requires the approved temporary HTTP ALB PublicUrl.'
  }
  $app = Wait-Argo
  Assert-ArgoHealthy $app

  $namespaceObject = Invoke-KubectlJson @('get', 'namespace', $Namespace)
  foreach ($mode in @('enforce', 'warn', 'audit')) {
    if ($namespaceObject.metadata.labels."pod-security.kubernetes.io/$mode" -ne 'restricted') {
      throw "Namespace Pod Security $mode is not restricted."
    }
  }

  $deployments = Invoke-KubectlJson @('-n', $Namespace, 'get', 'deployments')
  $names = @($deployments.items.metadata.name | Sort-Object)
  if (($names -join ',') -ne 'catalog-api,frontend,order-api') {
    throw "Unexpected deployment set: $($names -join ', ')."
  }
  foreach ($deployment in $deployments.items) {
    if ($deployment.status.availableReplicas -ne 1 -or $deployment.status.readyReplicas -ne 1) {
      throw "$($deployment.metadata.name) is not exactly one ready/available replica."
    }
  }

  $services = Invoke-KubectlJson @('-n', $Namespace, 'get', 'services')
  foreach ($service in $services.items) {
    if ($service.spec.type -ne 'ClusterIP') { throw "$($service.metadata.name) is publicly typed as $($service.spec.type)." }
  }
  $ingresses = Invoke-KubectlJson @('-n', $Namespace, 'get', 'ingresses')
  if ($ingresses.items.Count -ne 1) { throw "Expected one Ingress, found $($ingresses.items.Count)." }
  $backends = @($ingresses.items[0].spec.rules.http.paths.backend.service.name | Sort-Object -Unique)
  if (($backends -join ',') -ne 'frontend') { throw "Ingress exposes unexpected backend(s): $($backends -join ', ')." }

  $response = Invoke-WebRequest -Uri $PublicUrl -TimeoutSec 15
  if ($response.StatusCode -ne 200) { throw "Public frontend returned $($response.StatusCode)." }
  foreach ($header in @('Content-Security-Policy', 'Permissions-Policy', 'Referrer-Policy', 'X-Content-Type-Options')) {
    if (-not $response.Headers[$header]) { throw "Public response is missing $header." }
  }

  $requestId = "phase9-$([guid]::NewGuid())"
  $catalogResponse = Invoke-WebRequest -Uri "$($PublicUrl.TrimEnd('/'))/api/products" -Headers @{ 'x-request-id' = $requestId } -TimeoutSec 15
  if ($catalogResponse.StatusCode -ne 200 -or $catalogResponse.Headers['x-request-id'] -ne $requestId) {
    throw 'Public Catalog request did not preserve the request ID.'
  }
  Start-Sleep -Seconds 2
  $catalogLogs = & kubectl @kubectlContext -n $Namespace logs deployment/catalog-api --since=2m
  if ($LASTEXITCODE -ne 0 -or ($catalogLogs -join "`n") -notmatch [regex]::Escape($requestId)) {
    throw 'Catalog logs did not contain the propagated request ID.'
  }

  $canAdmin = & kubectl @kubectlContext auth can-i '*' '*' --as="system:serviceaccount:${Namespace}:frontend" -n $Namespace
  if ($LASTEXITCODE -ne 0 -or ($canAdmin -join '').Trim() -ne 'no') {
    throw 'Frontend ServiceAccount unexpectedly has Kubernetes API permissions.'
  }
  Write-Host "Phase 9 AWS baseline passed at $(Get-Date -Format o); revision=$($app.status.sync.revision); public-only frontend and request-ID correlation verified."
  exit 0
}

if ($Action -eq 'SelfHeal') {
  $before = Wait-Argo
  Assert-ArgoHealthy $before
  & kubectl @kubectlContext -n $Namespace scale deployment/frontend --replicas=2
  if ($LASTEXITCODE -ne 0) { throw 'Could not introduce the controlled replica drift.' }
  & kubectl @kubectlContext -n argocd annotate application $Application argocd.argoproj.io/refresh=hard --overwrite
  if ($LASTEXITCODE -ne 0) { throw 'Could not request an Argo CD refresh.' }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $frontend = Invoke-KubectlJson @('-n', $Namespace, 'get', 'deployment', 'frontend')
    $app = Get-Application
    if ($frontend.spec.replicas -eq 1 -and $frontend.status.readyReplicas -eq 1 -and
        $app.status.sync.status -eq 'Synced' -and $app.status.health.status -eq 'Healthy') {
      Write-Host "Argo CD self-heal passed at $(Get-Date -Format o); controlled frontend replica drift converged 2 -> 1."
      exit 0
    }
    Start-Sleep -Seconds 5
  } while ((Get-Date) -lt $deadline)
  throw 'Argo CD did not self-heal frontend replicas back to one.'
}

if (-not $ExpectedRevision) { throw 'WaitRevision requires ExpectedRevision (full SHA or unique prefix).' }
$app = Wait-Argo $ExpectedRevision
Assert-ImageTag $ExpectedImageTag
Write-Host "Argo CD revision gate passed at $(Get-Date -Format o); revision=$($app.status.sync.revision); imageTag=$ExpectedImageTag."
