variable "name" {
  description = "Name prefix, for example harbor-goods-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the cluster."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the VPC. The access instance may only open HTTPS connections inside it."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the access instance."
  type        = string
}

variable "cluster_security_group_id" {
  description = "Cluster security group. It gets one HTTPS rule from the access instance."
  type        = string
}

variable "node_role_names" {
  description = "Node IAM roles allowed to fill pull-through cache repositories on first pull."
  type        = list(string)
}

variable "karpenter_node_role_name" {
  description = "Karpenter node role. A private VPC has no IAM endpoint, so its instance profile is created here instead of by Karpenter."
  type        = string
}

variable "instance_type" {
  description = "Instance type of the access instance. It only relays Session Manager port forwarding."
  type        = string
  default     = "t4g.nano"
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
