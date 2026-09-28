# Private access to a cluster whose API endpoint is private in every environment:
#   - a relay instance with no public IP and no inbound rules; operators and Terraform reach
#     the private API endpoint through Session Manager port forwarding over the VPC endpoints
#     (scripts/api-tunnel.sh);
# and, when pull_through_cache is true (private-only live runs, no internet path):
#   - ECR pull-through cache rules, so nodes pull public images through ECR instead of the
#     internet;
#   - the Karpenter node instance profile, because Karpenter cannot reach IAM from the VPC.

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  partition = data.aws_partition.current.partition
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.region

  # Upstream registries the cluster pulls from, keyed by the ECR repository prefix.
  pull_through = var.pull_through_cache ? {
    "${var.name}-ecr-public" = "public.ecr.aws"
    "${var.name}-k8s"        = "registry.k8s.io"
  } : {}
}

data "aws_iam_policy_document" "access_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "access" {
  name               = "${var.name}-private-access"
  assume_role_policy = data.aws_iam_policy_document.access_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "access_ssm" {
  role       = aws_iam_role.access.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "access" {
  name = "${var.name}-private-access"
  role = aws_iam_role.access.name

  tags = var.tags
}

resource "aws_security_group" "access" {
  name        = "${var.name}-private-access"
  description = "Session Manager relay: no inbound rules, HTTPS out to the VPC only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-private-access" })
}

resource "aws_vpc_security_group_egress_rule" "access_https" {
  security_group_id = aws_security_group.access.id
  description       = "HTTPS to VPC endpoints and the private API endpoint"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_access" {
  security_group_id            = var.cluster_security_group_id
  description                  = "Kubernetes API from the Session Manager relay"
  referenced_security_group_id = aws_security_group.access.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_instance" "access" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.access.id]
  iam_instance_profile        = aws_iam_instance_profile.access.name
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = "${var.name}-private-access" })
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = local.pull_through

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value
}

data "aws_default_tags" "current" {}

# Cache repositories are created on first pull, outside Terraform; the template gives them the
# same tags as everything else, including tags an account requires on create.
resource "aws_ecr_repository_creation_template" "pull_through" {
  for_each = local.pull_through

  prefix               = each.key
  description          = "Pull-through cache repositories for ${each.value}"
  applied_for          = ["PULL_THROUGH_CACHE"]
  image_tag_mutability = "IMMUTABLE"
  resource_tags        = merge(data.aws_default_tags.current.tags, var.tags)

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# The first pull of an image creates its cache repository, tags it from the creation template
# and imports the image from upstream.
data "aws_iam_policy_document" "pull_through" {
  statement {
    actions = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository", "ecr:TagResource"]
    resources = [
      for prefix in keys(local.pull_through) : "arn:${local.partition}:ecr:${local.region}:${local.account}:repository/${prefix}/*"
    ]
  }
}

resource "aws_iam_role_policy" "pull_through" {
  for_each = var.pull_through_cache ? toset(var.node_role_names) : toset([])

  name   = "ecr-pull-through-cache"
  role   = each.value
  policy = data.aws_iam_policy_document.pull_through.json
}

resource "aws_iam_instance_profile" "karpenter_node" {
  count = var.pull_through_cache ? 1 : 0

  name = var.karpenter_node_role_name
  role = var.karpenter_node_role_name

  tags = var.tags
}
