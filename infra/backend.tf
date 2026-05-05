# infra/backend.tf
terraform {
  backend "s3" {
    bucket         = "tito-terraform-demo-state"
    key            = "session3/demo-a-ec2/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-demo-locks"
    encrypt        = true
  }
}
