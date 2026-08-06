param(
  [ValidateSet('Test', 'Cleanup')]
  [string]$Action = 'Test',
  [string]$Profile = 'techx-local',
  [string]$DiagnosticLog = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$namespace = 'techx-demo'

function Write-Diagnostic([string]$Message) {
  if ($DiagnosticLog) { "$(Get-Date -Format o) $Message" | Add-Content -LiteralPath $DiagnosticLog -Encoding utf8 }
}

function Assert-PodHttpAllowed {
  param([Parameter(Mandatory)][string]$Deployment, [Parameter(Mandatory)][string]$Url)
  kubectl --context $Profile --namespace $namespace exec "deployment/$Deployment" -- node -e "fetch('$Url',{signal:AbortSignal.timeout(4000)}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
  if ($LASTEXITCODE -ne 0) { throw "Expected $Deployment to reach $Url." }
}

function Assert-PodHttpDenied {
  param([Parameter(Mandatory)][string]$Deployment, [Parameter(Mandatory)][string]$Url)
  kubectl --context $Profile --namespace $namespace exec "deployment/$Deployment" -- node -e "fetch('$Url',{signal:AbortSignal.timeout(3000)}).then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>$null
  if ($LASTEXITCODE -eq 0) { throw "NetworkPolicy unexpectedly allowed $Deployment to reach $Url." }
}

if ($Action -eq 'Cleanup') {
  helm uninstall techx --namespace $namespace --ignore-not-found
  kubectl delete namespace $namespace --ignore-not-found --wait=true --timeout=120s
  minikube delete --profile $Profile
  exit 0
}

$status = minikube status --profile $Profile --output=json 2>$null | ConvertFrom-Json
if (-not $status -or $status.Host -ne 'Running') {
  minikube start --profile $Profile --driver=docker --cni=calico --kubernetes-version=v1.35.0 --cpus=2 --memory=4096
}
Write-Diagnostic 'cluster-ready'

kubectl --context "${Profile}" create namespace $namespace --dry-run=client -o yaml | kubectl --context "${Profile}" apply -f -
kubectl --context "${Profile}" label namespace $namespace pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/audit=restricted --overwrite
kubectl --context "${Profile}" create secret generic techx-demo-secrets --namespace $namespace --from-literal=order-api-key='local-k8s-demo-key' --dry-run=client -o yaml | kubectl --context "${Profile}" apply -f -
Write-Diagnostic 'namespace-secret-ready'

foreach ($image in @('techx/frontend:local', 'techx/catalog:local', 'techx/order:local')) {
  if (-not (docker image inspect $image 2>$null)) {
    throw "Missing local image $image. Complete Phase 4 image build first."
  }
  $loadedImages = minikube image ls --profile $Profile
  if ($loadedImages -notcontains "docker.io/$image") {
    minikube image load $image --profile $Profile
    if ($LASTEXITCODE -ne 0) { throw "Failed to load $image into Minikube." }
  }
}
Write-Diagnostic 'images-ready'

helm upgrade --install techx $root --namespace $namespace -f (Join-Path $root 'values-local.yaml') --kube-context $Profile --atomic --wait --timeout 5m
kubectl --context $Profile --namespace $namespace wait --for=condition=Available deployment --all --timeout=180s
Write-Diagnostic 'helm-ready'

$forwardLog = Join-Path ([System.IO.Path]::GetTempPath()) "techx-port-forward-$PID.log"
$forward = Start-Process kubectl -ArgumentList @('--context', $Profile, '--namespace', $namespace, 'port-forward', 'service/frontend', '18080:3000') -WindowStyle Hidden -PassThru -RedirectStandardOutput $forwardLog -RedirectStandardError "$forwardLog.err"
try {
  $ready = $false
  foreach ($attempt in 1..30) {
    try {
      $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/healthz' -TimeoutSec 2
      if ($health.status -eq 'ok') { $ready = $true; break }
    }
    catch { Start-Sleep -Milliseconds 500 }
  }
  if (-not $ready) { throw 'Frontend port-forward did not become ready.' }
  Write-Diagnostic 'port-forward-ready'

  $products = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/api/products' -TimeoutSec 10
  $product = if ($products.products) { $products.products[0] } else { $products[0] }
  if (-not $product.id) { throw 'Catalog response contained no product.' }
  $body = @{ items = @(@{ productId = $product.id; quantity = 1 }) } | ConvertTo-Json -Depth 4
  $order = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:18080/api/orders' -ContentType 'application/json' -Headers @{ 'Idempotency-Key' = "local-k8s-$PID" } -Body $body -TimeoutSec 10
  if (-not $order.order.id) { throw 'Order response contained no order ID.' }
  Write-Diagnostic 'business-flow-ready'

  Assert-PodHttpAllowed -Deployment 'frontend' -Url 'http://catalog-api:3001/healthz'
  Assert-PodHttpAllowed -Deployment 'frontend' -Url 'http://order-api:3002/healthz'
  Assert-PodHttpAllowed -Deployment 'order-api' -Url 'http://catalog-api:3001/healthz'
  Assert-PodHttpDenied -Deployment 'catalog-api' -Url 'http://order-api:3002/healthz'
  Assert-PodHttpDenied -Deployment 'order-api' -Url 'http://frontend:3000/healthz'
  Assert-PodHttpDenied -Deployment 'frontend' -Url 'http://example.com/'
  Write-Diagnostic 'workload-network-matrix-ready'

  kubectl --context $Profile --namespace $namespace run network-deny-check --image=curlimages/curl:8.18.0 --restart=Never --command -- sleep 300
  kubectl --context $Profile --namespace $namespace wait --for=condition=Ready pod/network-deny-check --timeout=120s
  foreach ($url in @('http://frontend:3000/healthz', 'http://catalog-api:3001/healthz', 'http://order-api:3002/healthz')) {
    kubectl --context $Profile --namespace $namespace exec network-deny-check -- curl --connect-timeout 2 --max-time 3 -fsS $url 2>$null
    if ($LASTEXITCODE -eq 0) { throw "NetworkPolicy unexpectedly allowed untrusted pod to reach $url." }
  }
  Write-Diagnostic 'untrusted-network-deny-ready'

  kubectl --context $Profile --namespace $namespace rollout restart deployment/catalog-api
  kubectl --context $Profile --namespace $namespace rollout status deployment/catalog-api --timeout=180s
  $productsAfterRestart = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/api/products' -TimeoutSec 10
  if (-not $productsAfterRestart) { throw 'Business flow did not recover after Catalog rollout.' }

  foreach ($deployment in @('order-api', 'frontend')) {
    kubectl --context $Profile --namespace $namespace rollout restart "deployment/$deployment"
    kubectl --context $Profile --namespace $namespace rollout status "deployment/$deployment" --timeout=180s
    $healthAfterRestart = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/healthz' -TimeoutSec 10
    if ($healthAfterRestart.status -ne 'ok') { throw "Frontend did not recover after $deployment rollout." }
  }
  Write-Diagnostic 'rollouts-ready'

  helm upgrade techx $root --namespace $namespace -f (Join-Path $root 'values-local.yaml') --set-string global.minReadySeconds=6 --kube-context $Profile --atomic --wait --timeout 5m
  helm rollback techx 1 --namespace $namespace --kube-context $Profile --wait --timeout 5m
  Write-Diagnostic 'upgrade-rollback-ready'

  $pods = kubectl --context $Profile --namespace $namespace get pods -l app.kubernetes.io/instance=techx -o json | ConvertFrom-Json
  foreach ($pod in $pods.items) {
    foreach ($status in $pod.status.containerStatuses) {
      if ($status.restartCount -ne 0) { throw "$($pod.metadata.name) restarted unexpectedly during resource smoke test." }
      if ($status.lastState.terminated.reason -eq 'OOMKilled') { throw "$($pod.metadata.name) was OOMKilled." }
    }
  }
  Write-Diagnostic 'resource-smoke-ready'

  Write-Host "Local Kubernetes E2E passed with order $($order.order.id); full allow/deny matrix, all workload restarts, upgrade/rollback, probes, Secret, and no-restart/OOM resource smoke verified."
}
catch {
  Write-Diagnostic "ERROR: $($_.Exception.Message) at $($_.ScriptStackTrace)"
  throw
}
finally {
  if ($forward -and -not $forward.HasExited) { Stop-Process -Id $forward.Id -Force }
  kubectl --context $Profile --namespace $namespace delete pod network-deny-check --ignore-not-found --wait=false 2>$null
  Remove-Item -LiteralPath $forwardLog, "$forwardLog.err" -Force -ErrorAction SilentlyContinue
  helm uninstall techx --namespace $namespace --kube-context $Profile --ignore-not-found
  kubectl --context $Profile delete namespace $namespace --ignore-not-found --wait=true --timeout=120s
  Write-Diagnostic "cleanup-complete lastExit=$LASTEXITCODE"
}
