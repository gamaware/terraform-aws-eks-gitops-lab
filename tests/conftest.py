"""Shared helpers: render charts and Kustomize overlays offline and parse the YAML."""

import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
CHART = ROOT / "charts" / "storefront"
GITOPS = ROOT / "gitops"
ENVIRONMENTS = sorted(p.name for p in (GITOPS / "environments").iterdir() if p.is_dir())
KUBE_VERSION = "1.35.0"


def _docs(text):
    return [d for d in yaml.safe_load_all(text) if d]


def helm_template(*values_files, set_values=(), check=True):
    cmd = [
        "helm",
        "template",
        "storefront",
        str(CHART),
        "--namespace",
        "storefront",
        "--kube-version",
        KUBE_VERSION,
        "--skip-tests",
    ]
    for f in values_files:
        cmd += ["--values", str(f)]
    for s in set_values:
        cmd += ["--set", s]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if check and result.returncode != 0:
        raise AssertionError(f"helm template failed:\n{result.stderr}")
    return result


def kustomize(env):
    result = subprocess.run(
        ["kubectl", "kustomize", str(GITOPS / "environments" / env)],
        capture_output=True,
        text=True,
        check=True,
    )
    return _docs(result.stdout)


def by_kind(docs, kind):
    return {d["metadata"]["name"]: d for d in docs if d["kind"] == kind}


@pytest.fixture(scope="session", params=ENVIRONMENTS)
def env(request):
    return request.param


@pytest.fixture(scope="session")
def gitops_docs():
    return {e: kustomize(e) for e in ENVIRONMENTS}


@pytest.fixture(scope="session")
def chart_docs():
    return {
        e: _docs(helm_template(GITOPS / "environments" / e / "values" / "storefront.yaml").stdout) for e in ENVIRONMENTS
    }
