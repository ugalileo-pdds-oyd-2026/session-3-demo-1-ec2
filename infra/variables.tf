variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "name" {
  description = "Base name applied to all resources in this module"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance — region-specific, must match architecture"
  type        = string
  # us-west-2, Amazon Linux 2023, arm64: ami-023a34a1153befb51
}

variable "instance_type" {
  description = "EC2 instance type — must match AMI architecture (arm64 → t4g.*)"
  type        = string
  default     = "t4g.nano"
}
