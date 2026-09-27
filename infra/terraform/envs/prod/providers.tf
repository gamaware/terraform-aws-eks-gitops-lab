provider "aws" {
  region = var.region

  default_tags {
    tags = merge({
      Project     = "harbor-goods-eks"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = "terraform-aws-eks-gitops-lab"
    }, var.extra_tags)
  }
}

# Short-lived token from the AWS CLI at every run; no kubeconfig or static credentials.
provider "helm" {
  kubernetes = {
    host                   = module.platform.cluster_endpoint
    cluster_ca_certificate = base64decode(module.platform.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.platform.cluster_name, "--region", var.region]
    }
  }
}
