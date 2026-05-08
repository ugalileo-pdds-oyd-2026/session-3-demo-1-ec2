variable "ami_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "environment" {
  type    = string
  default = "dev"
}
