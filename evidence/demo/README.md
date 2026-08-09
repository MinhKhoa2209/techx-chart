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
