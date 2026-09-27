# Partial configuration: bucket and region come from -backend-config at init time, so no
# account-specific name is committed. S3 native locking replaces the DynamoDB lock table.
terraform {
  backend "s3" {
    key          = "eks-gitops-lab/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
