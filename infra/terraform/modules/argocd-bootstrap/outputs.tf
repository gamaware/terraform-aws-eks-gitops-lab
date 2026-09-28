output "root_application_path" {
  description = "Repository path the root Application syncs."
  value       = local.root_path
}

output "argocd_namespace" {
  description = "Namespace where Argo CD runs."
  value       = helm_release.argocd.namespace
}
