"""Render assertions for the Argo CD app-of-apps in gitops/environments/<env>.

kubeconform proves each object is well formed; these tests prove the objects agree with each
other: projects allow what applications use, paths point at the right environment, and sync
waves install controllers before the resources that need them.
"""

import re
from pathlib import Path

import yaml

from conftest import GITOPS, ROOT, by_kind

CONTROLLERS = ("aws-load-balancer-controller", "karpenter", "metrics-server", "namespaces")


def _wave(app):
    return int(app["metadata"].get("annotations", {}).get("argocd.argoproj.io/sync-wave", "0"))


def test_no_placeholder_is_left(env, gitops_docs):
    assert "ENVIRONMENT" not in yaml.safe_dump_all(gitops_docs[env])


def test_every_application_uses_a_defined_project(env, gitops_docs):
    projects = by_kind(gitops_docs[env], "AppProject")
    for name, app in by_kind(gitops_docs[env], "Application").items():
        assert app["spec"]["project"] in projects, f"{name} uses an undefined project"


def test_projects_allow_each_source_and_destination(env, gitops_docs):
    projects = by_kind(gitops_docs[env], "AppProject")
    for name, app in by_kind(gitops_docs[env], "Application").items():
        project = projects[app["spec"]["project"]]["spec"]
        assert app["spec"]["source"]["repoURL"] in project["sourceRepos"], name
        allowed = {d["namespace"] for d in project["destinations"]}
        assert app["spec"]["destination"]["namespace"] in allowed, name


def test_catalog_api_project_cannot_create_cluster_resources(gitops_docs):
    for docs in gitops_docs.values():
        project = by_kind(docs, "AppProject")["catalog-api"]["spec"]
        assert project["clusterResourceWhitelist"] == []


THIS_REPO_LABEL = "harbor-goods.example.com/source"


def test_objects_reading_this_repository_are_labelled_for_the_root_patch(env, gitops_docs):
    # argocd-bootstrap patches labelled objects: repoURL and targetRevision on Applications,
    # sourceRepos[0] on AppProjects. Unlabelled objects would stay pinned to main.
    repo = "https://github.com/gamaware/terraform-aws-eks-gitops-lab.git"
    for name, app in by_kind(gitops_docs[env], "Application").items():
        labelled = app["metadata"].get("labels", {}).get(THIS_REPO_LABEL) == "this-repo"
        assert labelled == (app["spec"]["source"]["repoURL"] == repo), name
    for name, project in by_kind(gitops_docs[env], "AppProject").items():
        assert project["metadata"]["labels"][THIS_REPO_LABEL] == "this-repo", name
        assert project["spec"]["sourceRepos"][0] == repo, name


def test_repository_paths_exist_and_belong_to_the_environment(env, gitops_docs):
    for name, app in by_kind(gitops_docs[env], "Application").items():
        source = app["spec"]["source"]
        if "path" not in source:
            continue
        path = ROOT / source["path"]
        assert path.is_dir(), f"{name}: {source['path']} does not exist"
        if source["path"].startswith("gitops/environments/"):
            assert source["path"].split("/")[2] == env, f"{name} points at another environment"
        for values_file in source.get("helm", {}).get("valueFiles", []):
            resolved = (path / values_file).resolve()
            assert resolved.is_file(), f"{name}: {values_file} does not exist"
            assert resolved.is_relative_to(GITOPS / "environments" / env), f"{name} reads another environment's values"


def test_sync_waves_install_controllers_first(env, gitops_docs):
    apps = by_kind(gitops_docs[env], "Application")
    controllers = max(_wave(apps[c]) for c in CONTROLLERS)
    assert _wave(apps["karpenter-nodepools"]) > controllers, "NodePools need the Karpenter CRDs"
    assert _wave(apps["catalog-api"]) > _wave(apps["karpenter-nodepools"]), "the app needs nodes and the ALB webhook"


def test_every_application_prunes_and_self_heals(env, gitops_docs):
    for name, app in by_kind(gitops_docs[env], "Application").items():
        automated = app["spec"]["syncPolicy"]["automated"]
        assert automated == {"prune": True, "selfHeal": True}, name


def test_third_party_charts_are_pinned(env, gitops_docs):
    for name, app in by_kind(gitops_docs[env], "Application").items():
        source = app["spec"]["source"]
        if "chart" in source:
            assert re.fullmatch(r"\d+\.\d+\.\d+", source["targetRevision"]), f"{name} floats"


def test_load_balancer_controller_matches_the_vendored_iam_policy(env, gitops_docs):
    app = by_kind(gitops_docs[env], "Application")["aws-load-balancer-controller"]
    version = app["spec"]["source"]["targetRevision"]
    policy = ROOT / "infra/terraform/modules/eks/policies" / f"aws-load-balancer-controller-v{version}.json"
    assert policy.is_file(), f"no vendored IAM policy for controller {version}"


def test_catalog_api_namespace_enforces_restricted_pod_security(env, gitops_docs):
    apps = by_kind(gitops_docs[env], "Application")
    assert apps["namespaces"]["spec"]["project"] == "platform", "the workload team must not own its namespace"
    assert "syncOptions" not in apps["catalog-api"]["spec"]["syncPolicy"], "catalog-api must not create namespaces"
    namespace = yaml.safe_load((GITOPS / "namespaces" / "catalog-api.yaml").read_text())
    assert namespace["metadata"]["labels"]["pod-security.kubernetes.io/enforce"] == "restricted"


def test_environment_names_are_consistent(env, gitops_docs):
    cluster = f"harbor-goods-{env}"
    apps = by_kind(gitops_docs[env], "Application")
    lbc = apps["aws-load-balancer-controller"]["spec"]["source"]["helm"]["valuesObject"]
    karpenter = apps["karpenter"]["spec"]["source"]["helm"]["valuesObject"]["settings"]
    assert lbc["clusterName"] == cluster
    assert lbc["vpcTags"] == {"Name": cluster}
    assert karpenter == {"clusterName": cluster, "interruptionQueue": f"{cluster}-karpenter"}

    node_class = yaml.safe_load((GITOPS / "environments" / env / "karpenter" / "ec2nodeclass.yaml").read_text())
    assert node_class["spec"]["role"] == f"{cluster}-karpenter-node"
    for terms in ("subnetSelectorTerms", "securityGroupSelectorTerms"):
        assert node_class["spec"][terms] == [{"tags": {"karpenter.sh/discovery": cluster}}]


def test_karpenter_nodes_are_pinned_and_hardened(env):
    folder = GITOPS / "environments" / env / "karpenter"
    node_class = yaml.safe_load((folder / "ec2nodeclass.yaml").read_text())
    node_pool = yaml.safe_load((folder / "nodepool.yaml").read_text())

    alias = node_class["spec"]["amiSelectorTerms"][0]["alias"]
    assert re.fullmatch(r"al2023@v\d{8}", alias), f"AMI alias must be pinned, got {alias}"
    assert node_class["spec"]["metadataOptions"]["httpTokens"] == "required"
    assert node_class["spec"]["metadataOptions"]["httpPutResponseHopLimit"] == 1
    assert node_pool["spec"]["template"]["spec"]["nodeClassRef"]["name"] == node_class["metadata"]["name"]
    assert "cpu" in node_pool["spec"]["limits"], "an unbounded NodePool can scale without limit"


def test_prod_ami_is_not_newer_than_dev():
    def release(env):
        node_class = yaml.safe_load((GITOPS / "environments" / env / "karpenter" / "ec2nodeclass.yaml").read_text())
        return node_class["spec"]["amiSelectorTerms"][0]["alias"].split("@v")[1]

    assert release("prod") <= release("dev"), "prod must run an AMI release dev has already run"


def test_catalog_api_lands_on_the_workloads_node_pool(env, chart_docs):
    deployment = by_kind(chart_docs[env], "Deployment")["catalog-api"]
    selector = deployment["spec"]["template"]["spec"]["nodeSelector"]["karpenter.sh/nodepool"]
    node_pool = yaml.safe_load(Path(GITOPS / "environments" / env / "karpenter" / "nodepool.yaml").read_text())
    assert selector == node_pool["metadata"]["name"]
