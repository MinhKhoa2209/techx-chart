from __future__ import annotations

import collections
import pathlib
import sys

import yaml


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


rendered = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig")
docs = [doc for doc in yaml.safe_load_all(rendered) if doc]
by_kind = collections.defaultdict(list)
for doc in docs:
    by_kind[doc["kind"]].append(doc)

require(len(by_kind["Deployment"]) == 3, "expected exactly three Deployments")
require(len(by_kind["Service"]) == 3, "expected exactly three Services")
require(len(by_kind["ServiceAccount"]) == 3, "expected exactly three ServiceAccounts")
require(len(by_kind["Ingress"]) == 1, "expected exactly one Ingress")
require(not by_kind["Secret"], "chart must not render a Secret")

expected = {"frontend", "catalog-api", "order-api"}
for kind in ("Deployment", "Service", "ServiceAccount"):
    require({item["metadata"]["name"] for item in by_kind[kind]} == expected, f"unexpected {kind} set")

for service in by_kind["Service"]:
    require(service["spec"]["type"] == "ClusterIP", "all Services must remain ClusterIP")

ingress = by_kind["Ingress"][0]
paths = ingress["spec"]["rules"][0]["http"]["paths"]
require(len(paths) == 1, "Ingress must expose one route")
require(paths[0]["path"] == "/", "Ingress must only expose the root prefix")
require(paths[0]["backend"]["service"]["name"] == "frontend", "Ingress must only target frontend")
require(ingress["spec"]["ingressClassName"] == "alb", "demo Ingress must use ALB")

for deployment in by_kind["Deployment"]:
    name = deployment["metadata"]["name"]
    spec = deployment["spec"]
    pod = spec["template"]["spec"]
    container = pod["containers"][0]
    require(pod["automountServiceAccountToken"] is False, f"{name} must disable token automount")
    require(pod["securityContext"]["runAsNonRoot"] is True, f"{name} must run non-root")
    require(container["securityContext"]["readOnlyRootFilesystem"] is True, f"{name} root fs must be read-only")
    require(container["securityContext"]["capabilities"]["drop"] == ["ALL"], f"{name} must drop all capabilities")
    require(container["startupProbe"]["httpGet"]["path"] == "/healthz", f"{name} startup probe mismatch")
    require(container["livenessProbe"]["httpGet"]["path"] == "/healthz", f"{name} liveness probe mismatch")
    require(container["readinessProbe"]["httpGet"]["path"] == "/readyz", f"{name} readiness probe mismatch")
    require(container["resources"]["requests"] and container["resources"]["limits"], f"{name} resources missing")
    require(spec["strategy"]["type"] == ("Recreate" if name == "order-api" else "RollingUpdate"), f"{name} rollout strategy mismatch")

policy_names = {item["metadata"]["name"] for item in by_kind["NetworkPolicy"]}
require(policy_names == {"default-deny", "allow-dns", "frontend-ingress", "frontend-egress", "catalog-ingress", "order-ingress", "order-egress"}, "NetworkPolicy matrix mismatch")
require("replace-with" not in rendered, "placeholder secret leaked into rendered YAML")
require("kind: LoadBalancer" not in rendered and "type: NodePort" not in rendered, "backend public endpoint rendered")

app_path = pathlib.Path(__file__).parents[1] / "gitops" / "clusters" / "demo" / "application.yaml"
app = yaml.safe_load(app_path.read_text(encoding="utf-8"))
require(app["spec"]["source"]["helm"]["valueFiles"] == ["values-demo.yaml"], "Argo value file mismatch")
require(app["spec"]["syncPolicy"]["automated"] == {"prune": True, "selfHeal": True, "allowEmpty": False}, "Argo automated sync mismatch")
require("resources-finalizer.argocd.argoproj.io" in app["metadata"]["finalizers"], "Argo finalizer missing")
require("CreateNamespace=true" in app["spec"]["syncPolicy"]["syncOptions"], "Argo namespace creation missing")

print("Helm manifest and Argo CD assertions passed.")

