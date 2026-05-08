module "compute_ec2" {
  source = "./modules/compute_ec2"

  environment         = var.environment
  name                = var.name
  ami_id              = var.ami_id
  instance_type       = var.instance_type
  app_s3_bucket       = var.app_s3_bucket
  allowed_cidr_blocks = var.allowed_cidr_blocks
}
