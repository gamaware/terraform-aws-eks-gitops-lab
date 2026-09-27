# Offline: providers are mocked. These runs check that the names Terraform creates are the
# names gitops/environments/dev references, so a rename on one side fails here, not in the
# cluster.
mock_provider "aws" {
  source = "../../tests/mocks"
}

mock_provider "helm" {}

variables {
  admin_role_arns     = ["arn:aws:iam::111122223333:role/HarborGoodsPlatformAdmin"]
  public_access_cidrs = ["203.0.113.10/32"]
}

run "terraform_and_gitops_agree_on_names" {
  command = apply

  assert {
    condition     = module.platform.cluster_name == yamldecode(file("../../../../gitops/environments/dev/patches/karpenter.yaml")).spec.source.helm.valuesObject.settings.clusterName
    error_message = "Karpenter settings.clusterName must equal the Terraform cluster name."
  }

  assert {
    condition     = module.platform.karpenter_interruption_queue_name == yamldecode(file("../../../../gitops/environments/dev/patches/karpenter.yaml")).spec.source.helm.valuesObject.settings.interruptionQueue
    error_message = "Karpenter settings.interruptionQueue must equal the queue Terraform creates."
  }

  assert {
    condition     = module.platform.karpenter_node_role_name == yamldecode(file("../../../../gitops/environments/dev/karpenter/ec2nodeclass.yaml")).spec.role
    error_message = "The EC2NodeClass role must be the node role Terraform creates."
  }

  assert {
    condition     = yamldecode(file("../../../../gitops/environments/dev/karpenter/ec2nodeclass.yaml")).spec.subnetSelectorTerms[0].tags["karpenter.sh/discovery"] == module.platform.cluster_name
    error_message = "The EC2NodeClass subnet selector must match the discovery tag on the private subnets."
  }

  assert {
    condition     = yamldecode(file("../../../../gitops/environments/dev/patches/aws-load-balancer-controller.yaml")).spec.source.helm.valuesObject.vpcTags.Name == module.platform.cluster_name
    error_message = "The load balancer controller finds the VPC by its Name tag, which Terraform sets to the cluster name."
  }

  assert {
    condition     = yamldecode(file("../../../../gitops/environments/dev/patches/aws-load-balancer-controller.yaml")).spec.source.helm.valuesObject.clusterName == module.platform.cluster_name
    error_message = "The load balancer controller clusterName must equal the Terraform cluster name."
  }

  assert {
    condition     = module.platform.argocd_root_path == "gitops/environments/dev"
    error_message = "The root Application must sync this environment's folder."
  }
}

run "environment_sizing" {
  command = apply

  assert {
    condition     = module.platform.nat_gateway_count == 1
    error_message = "Dev shares one NAT gateway to save cost."
  }
}
