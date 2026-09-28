#!/usr/bin/env python3
"""Refuse a Terraform plan that would create or change an internet-facing resource.

Live tests run private-only. scripts/test-live.sh saves the plan, converts it with
`terraform show -json` and runs this check before `terraform apply`; any finding stops the run.

Usage: check_private_plan.py PLAN_JSON [--max-endpoint-cidrs N]

Allowed: egress-only paths (internet gateway, NAT gateway and its Elastic IP) and, when
--max-endpoint-cidrs is above 0, a public EKS API endpoint limited to that many /32 addresses.
Standard library only, so it runs before any dependency is installed.
"""

import argparse
import json
import sys

OPEN_CIDRS = {"0.0.0.0/0", "::/0"}
WRITE_ACTIONS = {"create", "update"}


def _open(cidrs):
    return sorted(OPEN_CIDRS.intersection(c for c in cidrs or [] if c))


def _is_true(value):
    return value is True or str(value).lower() == "true"


def findings(plan, max_endpoint_cidrs=0):
    """Return one message per internet-facing resource the plan would create or change."""
    changes = [rc for rc in plan.get("resource_changes", []) if WRITE_ACTIONS.intersection(rc["change"]["actions"])]
    nat_gateways = sum(1 for rc in changes if rc["type"] == "aws_nat_gateway")
    eips = 0
    found = []

    for rc in changes:
        kind, address = rc["type"], rc["address"]
        after = rc["change"].get("after") or {}

        def add(reason, address=address):
            found.append(f"{address}: {reason}")

        if kind in ("aws_lb", "aws_alb", "aws_elb") and not after.get("internal"):
            add("load balancer is internet-facing (internal = false)")
        elif kind == "aws_security_group":
            for rule in after.get("ingress") or []:
                opened = _open((rule.get("cidr_blocks") or []) + (rule.get("ipv6_cidr_blocks") or []))
                if opened:
                    add(f"security group ingress from {', '.join(opened)}")
        elif kind == "aws_security_group_rule" and after.get("type") == "ingress":
            opened = _open((after.get("cidr_blocks") or []) + (after.get("ipv6_cidr_blocks") or []))
            if opened:
                add(f"security group ingress from {', '.join(opened)}")
        elif kind == "aws_vpc_security_group_ingress_rule":
            opened = _open([after.get("cidr_ipv4"), after.get("cidr_ipv6")])
            if opened:
                add(f"security group ingress from {', '.join(opened)}")
        elif kind == "aws_instance" and _is_true(after.get("associate_public_ip_address")):
            add("instance gets a public IP address")
        elif kind == "aws_launch_template":
            for interface in after.get("network_interfaces") or []:
                if _is_true(interface.get("associate_public_ip_address")):
                    add("launch template assigns public IP addresses")
        elif kind == "aws_subnet" and after.get("map_public_ip_on_launch"):
            add("subnet assigns public IP addresses on launch")
        elif kind in ("aws_db_instance", "aws_rds_cluster_instance") and after.get("publicly_accessible"):
            add("database is publicly accessible")
        elif kind == "aws_s3_bucket_public_access_block":
            flags = ("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")
            if not all(after.get(flag) for flag in flags):
                add("bucket public access block is not fully enabled")
        elif kind == "aws_lambda_function_url" and after.get("authorization_type") == "NONE":
            add("Lambda function URL allows unauthenticated calls")
        elif kind in ("aws_cloudfront_distribution", "aws_apigatewayv2_api", "aws_api_gateway_rest_api"):
            add("public endpoint service")
        elif kind == "aws_eip":
            eips += 1
        elif kind == "aws_eks_cluster":
            for vpc in after.get("vpc_config") or []:
                if not vpc.get("endpoint_public_access"):
                    continue
                cidrs = vpc.get("public_access_cidrs") or []
                if max_endpoint_cidrs == 0:
                    add("EKS API endpoint is public")
                elif not cidrs or len(cidrs) > max_endpoint_cidrs or not all(c.endswith("/32") for c in cidrs):
                    add(f"EKS API endpoint must allow at most {max_endpoint_cidrs} /32 address(es), got {cidrs}")

    if eips > nat_gateways:
        found.append(f"plan creates {eips} Elastic IPs for {nat_gateways} NAT gateways; extra public IPs are refused")
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("plan_json", help="output of terraform show -json <planfile>")
    parser.add_argument("--max-endpoint-cidrs", type=int, default=0)
    args = parser.parse_args(argv)

    with open(args.plan_json, encoding="utf-8") as handle:
        plan = json.load(handle)
    problems = findings(plan, args.max_endpoint_cidrs)
    for problem in problems:
        print(f"internet-facing: {problem}", file=sys.stderr)
    if problems:
        print("Refusing to apply: live tests run private-only.", file=sys.stderr)
        return 1
    print("private-only plan check: passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
