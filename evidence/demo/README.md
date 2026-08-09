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
