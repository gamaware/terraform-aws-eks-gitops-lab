# Offline: the Helm provider is mocked, so no cluster or chart download is needed.
mock_provider "helm" {}

variables {
  environment = "dev"
  repo_url    = "https://github.com/gamaware/terraform-aws-eks-gitops-lab.git"
}

run "root_application_syncs_the_environment_folder" {
  command = apply

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.source.path == "gitops/environments/dev"
    error_message = "The dev cluster must sync gitops/environments/dev and nothing else."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.syncPolicy.automated.selfHeal
    error_message = "Self-heal must be on so manual cluster edits are reverted to Git."
  }
}

run "children_follow_the_root_repository_and_revision" {
  command = apply

  variables {
    repo_url        = "https://github.com/example/fork.git"
    target_revision = "feat/try-this"
  }

  assert {
    condition = yamldecode(yamldecode(helm_release.root.values[0]).applications.root.source.kustomize.patches[0].patch) == [
      { op = "replace", path = "/spec/source/repoURL", value = "https://github.com/example/fork.git" },
      { op = "replace", path = "/spec/source/targetRevision", value = "feat/try-this" },
    ]
    error_message = "Child Applications reading this repository must follow the root's repository and revision."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.source.kustomize.patches[1].target.kind == "AppProject"
    error_message = "AppProjects must allow the repository the root reads."
  }
}

run "default_project_is_locked" {
  command = plan

  assert {
    condition     = length(yamldecode(helm_release.root.values[0]).projects.default.sourceRepos) == 0 && length(yamldecode(helm_release.root.values[0]).projects.default.destinations) == 0
    error_message = "The built-in default project must allow nothing."
  }
}

run "root_project_can_only_create_argo_cd_objects" {
  command = apply

  assert {
    condition     = length(yamldecode(helm_release.root.values[0]).projects.bootstrap.clusterResourceWhitelist) == 0
    error_message = "The bootstrap project must not create cluster-scoped resources."
  }

  assert {
    condition     = toset([for r in yamldecode(helm_release.root.values[0]).projects.bootstrap.namespaceResourceWhitelist : r.kind]) == toset(["Application", "AppProject"])
    error_message = "The bootstrap project may only create Applications and AppProjects."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).projects.bootstrap.sourceRepos == [var.repo_url]
    error_message = "The bootstrap project may only read this repository."
  }
}

run "charts_are_pinned" {
  command = plan

  assert {
    condition     = helm_release.argocd.version == "10.9.2" && helm_release.root.version == "2.0.5"
    error_message = "Chart versions must be pinned, not floating."
  }

  assert {
    condition     = yamldecode(helm_release.argocd.values[0]).server.service.type == "ClusterIP"
    error_message = "The Argo CD server must not be exposed through a load balancer."
  }
}

run "sync_waves_wait_for_child_application_health" {
  command = plan

  assert {
    condition     = strcontains(yamldecode(helm_release.argocd.values[0]).configs.cm["resource.customizations.health.argoproj.io_Application"], "obj.status.health.status")
    error_message = "Without the Application health check, sync waves in the app-of-apps do not wait for each other."
  }

  assert {
    condition     = yamldecode(helm_release.argocd.values[0]).configs.repositories.karpenter.enableOCI == "true"
    error_message = "The Karpenter chart is OCI-only; its repository must be registered with enableOCI."
  }
}

run "prod_syncs_the_prod_folder" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = output.root_application_path == "gitops/environments/prod"
    error_message = "The prod cluster must sync gitops/environments/prod."
  }
}

run "rejects_an_unknown_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "rejects_a_non_https_repository" {
  command = plan

  variables {
    repo_url = "git@github.com:gamaware/terraform-aws-eks-gitops-lab.git"
  }

  expect_failures = [var.repo_url]
}
