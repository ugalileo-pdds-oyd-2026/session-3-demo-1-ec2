module "compute_ec2" {
  source        = "./modules/compute_ec2"
  environment   = var.environment
  ami_id        = var.ami_id
  instance_type = var.instance_type
}
