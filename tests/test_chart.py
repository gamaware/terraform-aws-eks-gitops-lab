"""Render assertions for charts/catalog-api with each environment's values.

values.schema.json and the template guards must reject unsafe values, and the rendered
objects must keep the security and availability settings the environments rely on.
"""

import pytest

from conftest import by_kind, helm_template


def _pod(docs):
    return by_kind(docs, "Deployment")["catalog-api"]["spec"]["template"]["spec"]


def test_image_is_pinned_by_digest(env, chart_docs):
    image = _pod(chart_docs[env])["containers"][0]["image"]
    assert "@sha256:" in image


def test_pod_runs_restricted(env, chart_docs):
    pod = _pod(chart_docs[env])
    container = pod["containers"][0]
    assert pod["securityContext"]["runAsNonRoot"] is True
    assert pod["securityContext"]["runAsUser"] >= 10000
    assert pod["securityContext"]["seccompProfile"]["type"] == "RuntimeDefault"
    assert pod["automountServiceAccountToken"] is False
    assert container["securityContext"] == {
        "allowPrivilegeEscalation": False,
        "readOnlyRootFilesystem": True,
        "capabilities": {"drop": ["ALL"]},
    }


def test_probes_and_resources_are_set(env, chart_docs):
    container = _pod(chart_docs[env])["containers"][0]
    for probe in ("startupProbe", "readinessProbe", "livenessProbe"):
        assert probe in container
    assert set(container["resources"]["requests"]) == {"cpu", "memory"}
    assert set(container["resources"]["limits"]) == {"cpu", "memory"}


def test_prod_autoscales_and_dev_does_not(chart_docs):
    prod = chart_docs["prod"]
    hpa = by_kind(prod, "HorizontalPodAutoscaler")["catalog-api"]["spec"]
    assert (hpa["minReplicas"], hpa["maxReplicas"]) == (3, 12)
    assert "replicas" not in by_kind(prod, "Deployment")["catalog-api"]["spec"], "the HPA must own replicas"

    dev = chart_docs["dev"]
    assert not by_kind(dev, "HorizontalPodAutoscaler")
    assert by_kind(dev, "Deployment")["catalog-api"]["spec"]["replicas"] == 2


def test_disruption_budget_leaves_room_to_drain(env, chart_docs):
    docs = chart_docs[env]
    pdb = by_kind(docs, "PodDisruptionBudget")["catalog-api"]["spec"]["minAvailable"]
    hpa = by_kind(docs, "HorizontalPodAutoscaler")
    if hpa:
        floor = hpa["catalog-api"]["spec"]["minReplicas"]
    else:
        floor = by_kind(docs, "Deployment")["catalog-api"]["spec"]["replicas"]
    assert pdb < floor


def test_ingress_is_https_only_on_an_alb(env, chart_docs):
    ingress = by_kind(chart_docs[env], "Ingress")["catalog-api"]
    annotations = ingress["metadata"]["annotations"]
    assert ingress["spec"]["ingressClassName"] == "alb"
    assert annotations["alb.ingress.kubernetes.io/ssl-redirect"] == "443"
    assert annotations["alb.ingress.kubernetes.io/certificate-arn"].startswith("arn:aws:acm:")
    assert annotations["alb.ingress.kubernetes.io/ssl-policy"].startswith("ELBSecurityPolicy-TLS13")
    assert annotations["alb.ingress.kubernetes.io/target-type"] == "ip"


def test_network_policy_allows_dns_egress_only(env, chart_docs):
    policy = by_kind(chart_docs[env], "NetworkPolicy")["catalog-api"]["spec"]
    assert policy["policyTypes"] == ["Ingress", "Egress"]
    ports = {p["port"] for rule in policy["egress"] for p in rule["ports"]}
    assert ports == {53}


def test_every_object_is_namespaced_explicitly(env, chart_docs):
    for doc in chart_docs[env]:
        assert doc["metadata"]["namespace"] == "catalog-api", doc["kind"]


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        (["image.digest=", "image.tag=latest"], "/image/tag"),
        (["ingress.enabled=true", "ingress.certificateArn="], "/ingress"),
        (["containerPort=80"], "/containerPort"),
        (["replicaCount=2", "podDisruptionBudget.minAvailable=2"], "minAvailable must be below"),
        (["autoscaling.enabled=true", "autoscaling.minReplicas=1"], "minAvailable must be below"),
        (["resources.limits.cpu=null"], "/resources/limits"),
        (["debug=true"], "debug"),
    ],
    ids=[
        "latest-tag-without-digest",
        "ingress-without-certificate",
        "privileged-port",
        "pdb-blocks-drains",
        "hpa-floor-below-pdb",
        "missing-cpu-limit",
        "unknown-key",
    ],
)
def test_unsafe_values_are_rejected(overrides, message):
    result = helm_template(set_values=overrides, check=False)
    assert result.returncode != 0, f"{overrides} rendered without error"
    assert message in result.stderr
