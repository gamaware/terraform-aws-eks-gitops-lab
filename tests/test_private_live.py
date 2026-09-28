"""Live tests run private-only: what `make test-live` deploys must not be reachable from the
internet, must not use Route 53, and must work without an internet path. The repository's dev and
prod configurations keep their internet-facing ALB; scripts/live_install.py forces the live run
private, and these tests check what it produces.

scripts/test-live.sh runs this file as a pre-flight before it creates anything. The Terraform side
is checked by the dev, network and private-access `terraform test` runs and, on the saved plan, by
scripts/check_private_plan.py (tests/test_check_private_plan.py, plus the EKS and Route 53 rules
below).
"""

import importlib.util
import ipaddress

import pytest
import yaml

from conftest import ROOT, _docs, by_kind, helm_template, kustomize

LIVE_ENV = "dev"
DEV_VPC = ipaddress.ip_network("10.10.0.0/16")
REGISTRY = "111122223333.dkr.ecr.us-east-1.amazonaws.com"
PREFIXES = {"public.ecr.aws": "harbor-goods-dev-ecr-public", "registry.k8s.io": "harbor-goods-dev-k8s"}


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_private_plan = _load("check_private_plan")
live_install = _load("live_install")


def test_live_environment_has_no_load_balancer_services(chart_docs, gitops_docs):
    for doc in chart_docs[LIVE_ENV] + gitops_docs[LIVE_ENV]:
        if doc["kind"] == "Service":
            assert doc["spec"].get("type", "ClusterIP") != "LoadBalancer", doc["metadata"]["name"]


def test_live_environment_uses_no_route53(chart_docs, gitops_docs):
    names = {d["metadata"]["name"] for d in gitops_docs[LIVE_ENV] if d["kind"] == "Application"}
    assert "external-dns" not in names
    text = yaml.safe_dump_all(chart_docs[LIVE_ENV] + gitops_docs[LIVE_ENV]).lower()
    assert "external-dns" not in text
    assert "route53" not in text


def _plan(rtype, after):
    return {
        "resource_changes": [
            {"address": f"{rtype}.x", "mode": "managed", "type": rtype, "change": {"after": after}},
        ]
    }


@pytest.mark.parametrize(
    ("rtype", "after"),
    [
        (
            "aws_eks_cluster",
            {"vpc_config": [{"endpoint_public_access": True, "public_access_cidrs": ["203.0.113.10/32"]}]},
        ),
        ("aws_route53_zone", {"name": "example.com"}),
        ("aws_route53_record", {"name": "catalog.example.com"}),
    ],
)
def test_plan_check_refuses_public_endpoints_and_route53(rtype, after):
    assert check_private_plan.violations(_plan(rtype, after))


def test_plan_check_accepts_a_private_api_endpoint():
    after = {"vpc_config": [{"endpoint_private_access": True, "endpoint_public_access": False}]}
    assert check_private_plan.violations(_plan("aws_eks_cluster", after)) == []


@pytest.fixture(scope="module")
def live_install_dir(tmp_path_factory):
    out = tmp_path_factory.mktemp("live")
    live_install.prepare(kustomize(LIVE_ENV), out, REGISTRY, PREFIXES, "harbor-goods-dev-karpenter-node", str(DEV_VPC))
    return out


def _images(values):
    if isinstance(values, dict):
        for key, value in values.items():
            if key == "repository" and isinstance(value, str):
                yield value
            else:
                yield from _images(value)


def test_live_install_pulls_every_image_through_ecr(live_install_dir):
    files = sorted(live_install_dir.glob("*.values.yaml"))
    assert {f.name for f in files} == {f"{name}.values.yaml" for name in [*live_install.RELEASES, "catalog-api"]}
    for path in files:
        images = list(_images(yaml.safe_load(path.read_text())))
        assert images, path.name
        for image in images:
            assert image.startswith(f"{REGISTRY}/"), (path.name, image)


def test_live_install_keeps_the_pinned_chart_versions(live_install_dir):
    apps = by_kind(kustomize(LIVE_ENV), "Application")
    for line in (live_install_dir / "releases.tsv").read_text().splitlines():
        name, _chart, _repo, version, _namespace = line.split("\t")
        assert version == apps[name]["spec"]["source"]["targetRevision"], name


def test_live_karpenter_nodes_use_a_precreated_instance_profile(live_install_dir):
    docs = list(yaml.safe_load_all((live_install_dir / "karpenter.yaml").read_text()))
    node_class = by_kind(docs, "EC2NodeClass")["default"]["spec"]
    assert "role" not in node_class, "Karpenter cannot reach IAM from a VPC without internet"
    assert node_class["instanceProfile"] == "harbor-goods-dev-karpenter-node"
    assert node_class["associatePublicIPAddress"] is False


def test_live_install_tags_what_the_controllers_create(tmp_path):
    tags = {"purpose": "portfolio-test", "Team": "example"}
    live_install.prepare(
        kustomize(LIVE_ENV), tmp_path, REGISTRY, PREFIXES, "harbor-goods-dev-karpenter-node", str(DEV_VPC), tags
    )
    docs = list(yaml.safe_load_all((tmp_path / "karpenter.yaml").read_text()))
    node_tags = by_kind(docs, "EC2NodeClass")["default"]["spec"]["tags"]
    assert tags.items() <= node_tags.items()
    assert node_tags["ManagedBy"] == "karpenter", "the dev tags stay"
    lbc = yaml.safe_load((tmp_path / "aws-load-balancer-controller.values.yaml").read_text())
    assert tags.items() <= lbc["defaultTags"].items()


def test_live_karpenter_runs_in_isolated_vpc_mode(live_install_dir):
    values = yaml.safe_load((live_install_dir / "karpenter.values.yaml").read_text())
    assert values["settings"]["isolatedVPC"] is True


@pytest.fixture(scope="module")
def live_ingress(live_install_dir):
    docs = _docs(helm_template(live_install_dir / "catalog-api.values.yaml").stdout)
    return by_kind(docs, "Ingress")["catalog-api"]


def test_live_ingress_is_an_internal_alb(live_ingress):
    assert live_ingress["metadata"]["annotations"]["alb.ingress.kubernetes.io/scheme"] == "internal"


def test_live_alb_accepts_traffic_from_the_vpc_only(live_ingress):
    cidrs = live_ingress["metadata"]["annotations"]["alb.ingress.kubernetes.io/inbound-cidrs"].split(",")
    assert cidrs, "without inbound-cidrs the controller opens the ALB security group to 0.0.0.0/0"
    for cidr in cidrs:
        assert ipaddress.ip_network(cidr).subnet_of(DEV_VPC), cidr
