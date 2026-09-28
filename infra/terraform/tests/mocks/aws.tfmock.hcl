# Shared mock values for the AWS provider. Computed attributes that the provider validates
# as ARNs or JSON get realistic defaults using the AWS documentation account 111122223333.

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "111122223333"
  }
}

mock_data "aws_region" {
  defaults = {
    region = "us-east-1"
  }
}

mock_data "aws_eks_addon_version" {
  defaults = {
    version = "v1.0.0-eksbuild.1"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::111122223333:role/mock-role"
  }
}

mock_resource "aws_iam_policy" {
  defaults = {
    arn = "arn:aws:iam::111122223333:policy/mock-policy"
  }
}

mock_resource "aws_cloudwatch_log_group" {
  defaults = {
    arn = "arn:aws:logs:us-east-1:111122223333:log-group:mock"
  }
}

mock_resource "aws_kms_key" {
  defaults = {
    arn = "arn:aws:kms:us-east-1:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }
}

mock_resource "aws_eks_cluster" {
  defaults = {
    arn      = "arn:aws:eks:us-east-1:111122223333:cluster/mock"
    endpoint = "https://EXAMPLE0123456789.gr7.us-east-1.eks.amazonaws.com"
    certificate_authority = [
      { data = "bW9jay1jZXJ0aWZpY2F0ZQ==" }
    ]
  }
}

mock_resource "aws_eks_node_group" {
  defaults = {
    arn = "arn:aws:eks:us-east-1:111122223333:nodegroup/mock/system/mock"
  }
}

mock_resource "aws_sqs_queue" {
  defaults = {
    arn = "arn:aws:sqs:us-east-1:111122223333:mock"
    url = "https://sqs.us-east-1.amazonaws.com/111122223333/mock"
  }
}

mock_resource "aws_sns_topic" {
  defaults = {
    arn = "arn:aws:sns:us-east-1:111122223333:mock"
  }
}

mock_resource "aws_cloudwatch_event_rule" {
  defaults = {
    arn = "arn:aws:events:us-east-1:111122223333:rule/mock"
  }
}

mock_resource "aws_launch_template" {
  defaults = {
    id             = "lt-0123456789abcdef0"
    latest_version = 1
  }
}

mock_data "aws_ssm_parameter" {
  defaults = {
    insecure_value = "ami-0123456789abcdef0"
  }
}

mock_resource "aws_instance" {
  defaults = {
    id = "i-0123456789abcdef0"
  }
}
