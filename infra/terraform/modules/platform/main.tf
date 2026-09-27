# Composition used by every environment root: network, cluster, Karpenter prerequisites,
# observability and the Argo CD bootstrap. Environment roots only choose sizes and ranges.

locals {
  cluster_name = "${var.name}-${var.environment}"
  tags = merge(var.tags, {
    Environment = var.environment
  })
}

module "observability" {
  source = "../observability"

  cluster_name       = local.cluster_name
  log_retention_days = var.log_retention_days
  alarm_emails       = var.alarm_emails
  min_running_pods   = var.min_running_pods
  tags               = local.tags
}

module "network" {
  source = "../network"

  name               = local.cluster_name
  cluster_name       = local.cluster_name
  cidr               = var.vpc_cidr
  azs                = var.azs
  single_nat_gateway = var.single_nat_gateway
  kms_key_arn        = module.observability.kms_key_arn
  log_retention_days = var.log_retention_days
  tags               = local.tags
}

module "eks" {
  source = "../eks"

  cluster_name               = local.cluster_name
  kubernetes_version         = var.kubernetes_version
  subnet_ids                 = module.network.private_subnet_ids
  public_access_cidrs        = var.public_access_cidrs
  admin_role_arns            = var.admin_role_arns
  system_node_instance_types = var.system_node_instance_types
  system_node_count          = var.system_node_count
  logs_kms_key_arn           = module.observability.kms_key_arn
  log_retention_days         = var.log_retention_days
  tags                       = local.tags
}

module "karpenter" {
  source = "../karpenter"

  cluster_name = module.eks.cluster_name
  cluster_arn  = module.eks.cluster_arn
  tags         = local.tags
}

module "argocd" {
  source = "../argocd-bootstrap"

  environment     = var.environment
  repo_url        = var.gitops_repo_url
  target_revision = var.gitops_target_revision

  # Argo CD needs schedulable nodes, and Karpenter's IAM must exist before Argo CD installs it.
  depends_on = [module.eks, module.karpenter]
}
