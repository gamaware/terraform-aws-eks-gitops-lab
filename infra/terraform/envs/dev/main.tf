# Dev: one NAT gateway and a smaller system node group to keep the bill down. Everything else
# matches prod, so what passes here is what ships.
module "platform" {
  source = "../../modules/platform"

  environment        = "dev"
  kubernetes_version = "1.35"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  vpc_cidr           = "10.10.0.0/16"
  single_nat_gateway = true
  private_only       = var.private_only

  system_node_instance_types = ["m7i.large"]
  system_node_count = {
    min     = 2
    max     = 3
    desired = 2
  }

  public_access_cidrs    = var.public_access_cidrs
  admin_role_arns        = var.admin_role_arns
  alarm_emails           = var.alarm_emails
  min_running_pods       = { "catalog-api" = 1 }
  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision
}
