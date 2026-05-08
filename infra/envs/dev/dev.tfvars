ami_id        = "ami-0ddb64e71e68cf624"
instance_type = "t4g.nano"
environment   = "dev"
name          = "app"
app_s3_bucket = "tito-terraform-demo-app"
allowed_cidr_blocks = [
  "0.0.0.0/0"
]
