# The only Kubernetes objects Terraform manages: Argo CD itself and one root Application. The
# root Application points at gitops/environments/<env>; everything else in the cluster
# (controllers, Karpenter pools, the app) is reconciled from Git by Argo CD.

locals {
  root_path = "gitops/environments/${var.environment}"

  # Objects in gitops/ labelled as reading this repository follow the root Application's
  # repository and revision, so a branch or fork under test is used end to end.
  this_repo = { labelSelector = "harbor-goods.example.com/source=this-repo" }
  kustomize_patches = [
    {
      target = merge(local.this_repo, { kind = "Application" })
      patch = yamlencode([
        { op = "replace", path = "/spec/source/repoURL", value = var.repo_url },
        { op = "replace", path = "/spec/source/targetRevision", value = var.target_revision },
      ])
    },
    {
      target = merge(local.this_repo, { kind = "AppProject" })
      patch  = yamlencode([{ op = "replace", path = "/spec/sourceRepos/0", value = var.repo_url }])
    },
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.namespace
  create_namespace = true
  atomic           = true
  timeout          = 900

  values = [yamlencode({
    # Reach the UI through `kubectl port-forward`; no public Ingress for the control plane.
    server = {
      service = { type = "ClusterIP" }
    }
    dex = { enabled = false }
    global = {
      nodeSelector = { "harbor-goods.example.com/pool" = "system" }
    }
    configs = {
      # Karpenter publishes its chart only to an OCI registry. Public, so no credentials.
      repositories = {
        karpenter = {
          name      = "karpenter"
          type      = "helm"
          url       = "public.ecr.aws/karpenter"
          enableOCI = "true"
        }
      }
      cm = {
        # Argo CD does not assess child Application health by default, so sync waves in an
        # app-of-apps would not wait. This restores the check: wave 1 starts only once
        # wave 0 is Healthy.
        "resource.customizations.health.argoproj.io_Application" = file("${path.module}/application-health.lua")
      }
    }
  })]
}

resource "helm_release" "root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = var.namespace

  values = [yamlencode({
    # A narrow project for the root Application: it may only create Applications and
    # AppProjects in the Argo CD namespace, from this repository.
    projects = {
      # Argo CD's built-in project allows everything; empty it so no Application can use it.
      default = {
        namespace                  = var.namespace
        description                = "Locked: every Application must name a project"
        sourceRepos                = []
        destinations               = []
        clusterResourceWhitelist   = []
        namespaceResourceWhitelist = []
      }
      bootstrap = {
        namespace   = var.namespace
        description = "Root app-of-apps for ${var.environment}"
        sourceRepos = [var.repo_url]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }]
        clusterResourceWhitelist = []
        namespaceResourceWhitelist = [
          { group = "argoproj.io", kind = "Application" },
          { group = "argoproj.io", kind = "AppProject" },
        ]
      }
    }
    applications = {
      root = {
        namespace  = var.namespace
        project    = "bootstrap"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = local.root_path
          kustomize      = { patches = local.kustomize_patches }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
