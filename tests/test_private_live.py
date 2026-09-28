"""Live tests run private-only: the dev environment that `make test-live` deploys must not
create internet-facing resources.

scripts/test-live.sh runs this file as a pre-flight before it applies anything. The Terraform
side is checked twice: the dev and network `terraform test` runs assert the configuration, and
scripts/check_private_plan.py (tested here) refuses the saved plan itself.
"""

import importlib.util
import ipaddress
from pathlib import Path

import pytest
import yaml

from conftest import GITOPS, ROOT, by_kind

LIVE_ENV = "dev"
DEV_VPC = ipaddress.ip_network("10.10.0.0/16")

_spec = importlib.util.spec_from_file_location("check_private_plan", ROOT / "scripts" / "check_private_plan.py")
check_private_plan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_private_plan)


def test_live_ingress_is_an_internal_alb(chart_docs):
    ingress = by_kind(chart_docs[LIVE_ENV], "Ingress")["catalog-api"]
    assert ingress["metadata"]["annotations"]["alb.ingress.kubernetes.io/scheme"] == "internal"


def test_live_alb_accepts_traffic_from_the_vpc_only(chart_docs):
    annotations = by_kind(chart_docs[LIVE_ENV], "Ingress")["catalog-api"]["metadata"]["annotations"]
    cidrs = annotations["alb.ingress.kubernetes.io/inbound-cidrs"].split(",")
    assert cidrs, "without inbound-cidrs the controller opens the ALB security group to 0.0.0.0/0"
    for cidr in cidrs:
        assert ipaddress.ip_network(cidr).subnet_of(DEV_VPC), cidr


def test_live_environment_has_no_load_balancer_services(chart_docs, gitops_docs):
    for doc in chart_docs[LIVE_ENV] + gitops_docs[LIVE_ENV]:
        if doc["kind"] == "Service":
            assert doc["spec"].get("type", "ClusterIP") != "LoadBalancer", doc["metadata"]["name"]


@pytest.mark.parametrize("env_name", ["dev", "prod"])
def test_karpenter_nodes_never_get_public_ips(env_name):
    path = GITOPS / "environments" / env_name / "karpenter" / "ec2nodeclass.yaml"
    node_class = yaml.safe_load(Path(path).read_text())
    assert node_class["spec"]["associatePublicIPAddress"] is False


def _plan(*changes):
    return {
        "resource_changes": [
            {"address": f"{kind}.test{i}", "type": kind, "change": {"actions": ["create"], "after": after}}
            for i, (kind, after) in enumerate(changes)
        ]
    }


PRIVATE_EKS = {"vpc_config": [{"endpoint_public_access": True, "public_access_cidrs": ["203.0.113.10/32"]}]}


def test_plan_check_accepts_the_private_live_shape():
    plan = _plan(
        ("aws_eks_cluster", PRIVATE_EKS),
        ("aws_subnet", {"map_public_ip_on_launch": False}),
        ("aws_internet_gateway", {}),
        ("aws_eip", {"domain": "vpc"}),
        ("aws_nat_gateway", {}),
        ("aws_launch_template", {"network_interfaces": []}),
        ("aws_security_group", {"ingress": [{"cidr_blocks": ["10.10.0.0/16"]}]}),
    )
    assert check_private_plan.findings(plan, max_endpoint_cidrs=1) == []


@pytest.mark.parametrize(
    ("kind", "after"),
    [
        ("aws_lb", {"internal": False}),
        ("aws_security_group", {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}),
        ("aws_security_group", {"ingress": [{"ipv6_cidr_blocks": ["::/0"]}]}),
        ("aws_default_security_group", {"ingress": [{"cidr_blocks": ["0.0.0.0/0"]}]}),
        ("aws_security_group_rule", {"type": "ingress", "cidr_blocks": ["0.0.0.0/0"]}),
        ("aws_vpc_security_group_ingress_rule", {"cidr_ipv6": "::/0"}),
        ("aws_instance", {"associate_public_ip_address": True}),
        ("aws_launch_template", {"network_interfaces": [{"associate_public_ip_address": "true"}]}),
        ("aws_subnet", {"map_public_ip_on_launch": True}),
        ("aws_eip", {"domain": "vpc"}),
        ("aws_db_instance", {"publicly_accessible": True}),
        ("aws_eks_cluster", {"vpc_config": [{"endpoint_public_access": True, "public_access_cidrs": []}]}),
        ("aws_eks_cluster", {"vpc_config": [{"endpoint_public_access": True, "public_access_cidrs": ["0.0.0.0/0"]}]}),
        (
            "aws_eks_cluster",
            {"vpc_config": [{"endpoint_public_access": True, "public_access_cidrs": ["198.51.100.0/24"]}]},
        ),
    ],
)
def test_plan_check_refuses_internet_facing_resources(kind, after):
    assert check_private_plan.findings(_plan((kind, after)), max_endpoint_cidrs=1)


def test_plan_check_refuses_any_public_endpoint_by_default():
    assert check_private_plan.findings(_plan(("aws_eks_cluster", PRIVATE_EKS)))


def test_plan_check_ignores_deletes():
    plan = {
        "resource_changes": [
            {"address": "aws_lb.old", "type": "aws_lb", "change": {"actions": ["delete"], "after": None}}
        ]
    }
    assert check_private_plan.findings(plan) == []
