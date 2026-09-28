# Prod: one NAT gateway per AZ, so losing an AZ does not cut egress for the others, and a
# system node group spread across all three AZs.
module "platform" {
  source = "../../modules/platform"

  environment        = "prod"
  kubernetes_version = "1.35"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  vpc_cidr           = "10.20.0.0/16"
  single_nat_gateway = false

  system_node_instance_types = ["m7i.large"]
  system_node_count = {
    min     = 3
    max     = 5
    desired = 3
  }

  public_access_cidrs    = var.public_access_cidrs
  admin_role_arns        = var.admin_role_arns
  alarm_emails           = var.alarm_emails
  min_running_pods       = { "catalog-api" = 3 }
  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision
}
