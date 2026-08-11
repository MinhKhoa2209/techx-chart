# TechX demo evidence

Do not add kubeconfig, tokens, Secret values, Terraform state, full environment
dumps, or screenshots containing credentials.

For every accepted check, record the timestamp, Git commit, immutable image
digest, exact command, concise result, and a sanitized screenshot only when it
adds evidence beyond command output. Evidence must cover public-only frontend,
Argo CD ownership/self-heal, NetworkPolicy allow/deny, Git revert rollback, and
final teardown inventory.

## Phase 7 immutable artifacts

- Verified at: `2026-08-09T11:05:00+07:00`
- Platform commit/tag: `5a9137e2ed23e5322d4c8f9820f1ae6241ec0a4a` / `demo-5a9137e`
- `techx/frontend`: `sha256:1e2b84e0902770b3d0fddb494b19273a1204eb904c9315398270cc661a45ae68`
- `techx/catalog`: `sha256:c78b618287eb037ea1d3a5da066fea5957271415321305bcf248d8f8eead8ce9`
- `techx/order`: `sha256:c9256d847d2b668d32c2941149aa3eda41421dc3e748d0998c66cdbaffec2c2b`
- Verification: ECR scan status `COMPLETE`, zero `CRITICAL` findings for all
  three repositories; images were built and pushed for `linux/amd64`.

## Phase 8 GitOps and public acceptance

- Verified at: `2026-08-09T11:09:38+07:00`
- Chart commit: `dc7b632`
- Argo CD Application: `techx-demo`, status `Synced/Healthy`
- Workloads: `frontend`, `catalog-api`, and `order-api` all Available with one
  running pod and zero restarts.
- Temporary public URL:
  `http://k8s-techxdem-frontend-792ecd242c-1025349452.us-east-1.elb.amazonaws.com/`
- Public acceptance: root returned HTTP `200`; product list/detail, two order
  submissions covering both shipping rules, and order lookup passed through
  the frontend BFF.
- Exposure: one internet-facing ALB, one `HTTP:80` listener, one Ingress whose
  only backend is `frontend`; every Kubernetes Service, including Argo CD,
  remained `ClusterIP`.
- Security bootstrap: namespace enforced Pod Security `restricted`; the
  external Secret exposed only the expected `order-api-key` key name. Secret
  values were not collected.

## Immediate cost-safe teardown

- Teardown completed at: `2026-08-09T11:19:47+07:00`, before the approved
  `15:00 +07:00` deadline.
- The Argo CD Application was deleted with foreground cascading; its Ingress,
  ALB, target group, workload resources, and namespace disappeared before
  Terraform teardown began.
- Terraform destroy result: `35 destroyed`; the Terraform state resource list
  was empty.
- Immediate and delayed inventory checks found no TechX EKS cluster, ECR
  repository, ALB/target group, active EC2 instance, EBS volume, ENI, security
  group, VPC, CloudWatch log group, IAM role/policy, or project Budget.
- Resource Groups Tagging API briefly retained two historical instance and two
  volume ARNs. Direct EC2 checks proved both instances `terminated` and both
  volumes `NOT_FOUND`; this was tag-index lag, not live billable capacity.
- Billing was still delayed at collection time: Cost Explorer returned `0 USD`
  estimated for the project and account-plan credit remained `84.02 USD`.
- Local Compose containers and the `techx-local` Minikube profile were absent;
  Docker Desktop started for verification was stopped.

## Phase 9 local acceptance and current cloud state

- Verified at: `2026-08-11T21:19:01+07:00`.
- Platform commit: `409530f`; chart commit: `bb7198f`. The runtime source in
  the three images is unchanged from platform application commit `576e538`;
  `409530f` adds only the repeatable resilience gate and its documentation.
- Local Linux/AMD64 image content IDs:
  - frontend: `sha256:2c47d3bf71e4a3496f60b02641ada48c769afda48a802f5d6fc7b06d058b3b73`
  - catalog: `sha256:54255b1a034507c8cb45b96e54882bfa5905d20f014aa928f2f54a6c15e1517d`
  - order: `sha256:e2b8b20956fa986fefd2e8b3c53f03e837fd87ef3c56f66752059b74c2c747ec`
- Commands and concise results:
  - `techx-platform/scripts/verify.ps1`: 38 tests, TypeScript, formatting,
    lint, hard-code audit, and production build passed.
  - `docker compose build`, `docker compose up -d --wait`, then
    `container-smoke.ps1`, `container-recovery.ps1`,
    `container-resilience.ps1`, `container-soak.ps1 -DurationSeconds 60
    -BurstRequests 30`, and `container-audit.ps1`: passed. This proved
    concurrent idempotent double-submit (`201/200` with one order ID), bounded
    dependency `503`, Catalog recovery, documented Order data loss and service
    recovery after restart, request-ID correlation, secret log redaction,
    controlled `429`, no restart cascade, and hardened Linux/AMD64 containers.
  - `techx-chart/scripts/local-k8s.ps1 -Action Test` followed by `-Action
    Cleanup`: passed after correcting the test payload to the documented Order
    v2 contract. It proved the three workloads, probes, restricted namespace,
    Secret mount, full NetworkPolicy allow/deny matrix, untrusted-pod denial,
    all workload rollouts, Helm upgrade/rollback, no unexpected restart/OOM,
    uninstall, namespace deletion, and Minikube profile deletion.
  - `techx-chart/scripts/verify.ps1` and `techx-infra/scripts/verify.ps1`:
    Helm/schema/manifest/GitOps assertions and Terraform validate/static
    security checks passed.
- Read-only AWS inventory at the same checkpoint returned zero EKS clusters,
  zero `techx/` ECR repositories, zero active TechX load balancers, and zero
  non-terminated TechX EC2 instances in `us-east-1`. No AWS mutation was made.
- A second sanitized read-only preflight at `2026-08-11T21:33:59+07:00`
  confirmed EKS `1.35` in `STANDARD_SUPPORT`, six available AZs, `t3.medium` in
  five AZs, EKS cluster quota `100`, standard On-Demand quota `8` vCPUs, zero
  denied required actions, and zero resource-name conflicts. The 12-hour cost
  model returned a `9.03 USD` upper bound, below the `60 USD` apply gate and
  `80 USD` hard cap. This check was read-only and did not create a saved plan.
- Consequently, current-commit Argo self-heal, candidate image auto-sync, and
  rollback-by-`git revert` have **not** been claimed as executed. The repeatable
  `scripts/phase9-aws-acceptance.ps1` workflow (`Baseline`, `Resilience`,
  `SelfHeal`, and candidate/revert `WaitRevision`) is syntax/static verified, but it
  requires a newly reviewed plan and fresh owner approval before another apply.
  The Phase 8 cloud evidence above applies only to the older immutable
  `demo-5a9137e` deployment.
- No screenshots were added because sanitized command results are stronger for
  these local gates. No kubeconfig, token, Secret value, Terraform state, saved
  plan, or full environment dump was collected.

## Demo limitations

- The temporary entry point is HTTP on an ALB DNS name; there is no custom
  domain or TLS certificate in this internship thin slice.
- The cluster uses one node and is not a high-availability production design.
- Orders and idempotency records are in memory and are intentionally lost on an
  Order pod restart.
- No observability stack or public observability UI is deployed; JSON logs,
  probes, Kubernetes status, and private operator access are the scoped signals.
