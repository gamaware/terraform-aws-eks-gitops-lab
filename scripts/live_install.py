#!/usr/bin/env python3
"""Prepare the private-only live install of the dev environment.

Live tests run private-only, so Argo CD (which syncs from GitHub) is not installed. The operator
installs the same Helm releases the dev Argo CD Applications declare, at the same pinned versions
and values, through Session Manager port forwarding. Images come from ECR pull-through cache
repositories instead of their public registries, because the VPC has no internet path.

Usage:
    live_install.py APPS_YAML OUT_DIR --registry HOST --prefix UPSTREAM=PREFIX [...] --instance-profile NAME
                    --vpc-cidr CIDR [--tags JSON]

APPS_YAML is `kubectl kustomize gitops/environments/dev`. OUT_DIR receives:
    releases.tsv                 name, chart, repository ("-" for OCI), version, namespace
    <name>.values.yaml           values for each release, images rewritten to the registry
    catalog-api.values.yaml      the dev catalog-api values, image rewritten, ALB forced internal to the VPC
    karpenter.yaml               the dev NodePools and EC2NodeClass, with a pre-created instance profile and no
                                 public IP addresses

--tags adds AWS tags to what the controllers create: Karpenter's nodes and the load balancer controller's load
balancers, target groups and security groups, so they carry the same tags as the Terraform resources.

The repository's dev and prod configurations stay as designed (internet-facing ALB); only the live run is
forced private here.
"""

import argparse
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
ENV_DIR = ROOT / "gitops" / "environments" / "dev"
CHART_VALUES = ROOT / "charts" / "catalog-api" / "values.yaml"

# Releases the dev app-of-apps installs from Helm repositories, with the chart value that holds
# the container image repository and settings a VPC without internet needs.
RELEASES = {
    "karpenter": {
        "image_key": ("controller", "image", "repository"),
        "default_image": "public.ecr.aws/karpenter/controller",
        # No pricing API endpoint exists in the VPC; Karpenter uses its built-in price list.
        "extra": {"settings": {"isolatedVPC": True}},
    },
    "aws-load-balancer-controller": {
        "image_key": ("image", "repository"),
        "default_image": "public.ecr.aws/eks/aws-load-balancer-controller",
        # No Shield or WAF endpoints in the VPC, and the live Ingress uses neither.
        "extra": {"enableShield": False, "enableWaf": False, "enableWafv2": False},
    },
    "metrics-server": {
        "image_key": ("image", "repository"),
        "default_image": "registry.k8s.io/metrics-server/metrics-server",
        "extra": {},
    },
}


def rewrite(image, registry, prefixes):
    """Map an upstream image repository to its pull-through cache repository in ECR."""
    host, _, path = image.partition("/")
    if host not in prefixes:
        raise ValueError(f"no pull-through cache rule for {host} (image {image})")
    return f"{registry}/{prefixes[host]}/{path}"


def _set(values, keys, value):
    for key in keys[:-1]:
        values = values.setdefault(key, {})
    values[keys[-1]] = value


def _merge(base, extra):
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _merge(base[key], value)
        else:
            base[key] = value
    return base


def chart_reference(source):
    """(chart, repository) for an Argo CD Helm source; OCI charts have no repository."""
    repo = source["repoURL"].rstrip("/")
    if repo.startswith(("http://", "https://")):
        return source["chart"], repo
    return f"oci://{repo}/{source['chart']}", "-"


def prepare(apps_docs, out_dir, registry, prefixes, instance_profile, vpc_cidr, tags=None):
    tags = tags or {}
    apps = {d["metadata"]["name"]: d for d in apps_docs if d and d.get("kind") == "Application"}
    out_dir.mkdir(parents=True, exist_ok=True)

    lines = []
    for name, spec in RELEASES.items():
        app = apps[name]
        source = app["spec"]["source"]
        values = dict((source.get("helm") or {}).get("valuesObject") or {})
        _set(values, spec["image_key"], rewrite(spec["default_image"], registry, prefixes))
        _merge(values, spec["extra"])
        if name == "aws-load-balancer-controller" and tags:
            values["defaultTags"] = {**values.get("defaultTags", {}), **tags}
        (out_dir / f"{name}.values.yaml").write_text(yaml.safe_dump(values, sort_keys=True))
        namespace = app["spec"]["destination"]["namespace"]
        lines.append("\t".join([name, *chart_reference(source), source["targetRevision"], namespace]))
    (out_dir / "releases.tsv").write_text("\n".join(lines) + "\n")

    chart_defaults = yaml.safe_load(CHART_VALUES.read_text())
    dev_values = yaml.safe_load((ENV_DIR / "values" / "catalog-api.yaml").read_text())
    image = (dev_values.get("image") or {}).get("repository") or chart_defaults["image"]["repository"]
    dev_values.setdefault("image", {})["repository"] = rewrite(image, registry, prefixes)
    # Live tests run private-only: an internal ALB that accepts the VPC range, never 0.0.0.0/0.
    dev_values.setdefault("ingress", {}).update({"scheme": "internal", "inboundCidrs": [vpc_cidr]})
    (out_dir / "catalog-api.values.yaml").write_text(yaml.safe_dump(dev_values, sort_keys=True))

    manifests = []
    for path in sorted((ENV_DIR / "karpenter").glob("*.yaml")):
        for doc in yaml.safe_load_all(path.read_text()):
            if doc and doc["kind"] == "EC2NodeClass":
                # Karpenter would create an instance profile through IAM, which has no VPC endpoint.
                doc["spec"].pop("role", None)
                doc["spec"]["instanceProfile"] = instance_profile
                doc["spec"]["associatePublicIPAddress"] = False
                doc["spec"]["tags"] = {**doc["spec"].get("tags", {}), **tags}
            if doc:
                manifests.append(doc)
    (out_dir / "karpenter.yaml").write_text(yaml.safe_dump_all(manifests, sort_keys=False))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("apps_yaml", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--prefix", action="append", required=True, help="UPSTREAM=PREFIX, repeatable")
    parser.add_argument("--instance-profile", required=True)
    parser.add_argument("--vpc-cidr", required=True)
    parser.add_argument("--tags", type=json.loads, default={}, help="JSON object of AWS tags")
    args = parser.parse_args(argv)

    prefixes = dict(item.split("=", 1) for item in args.prefix)
    docs = list(yaml.safe_load_all(args.apps_yaml.read_text()))
    prepare(docs, args.out_dir, args.registry, prefixes, args.instance_profile, args.vpc_cidr, args.tags)
    print(f"live install prepared in {args.out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
