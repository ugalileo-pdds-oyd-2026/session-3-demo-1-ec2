output "compute_ec2_instance_id" {
  description = "The ID of the EC2 instance created by the compute_ec2 module."
  value       = module.compute_ec2.instance_id
}

output "compute_ec2_public_ip" {
  description = "The public IP address of the EC2 instance created by the compute_ec2 module."
  value       = module.compute_ec2.public_ip
}
