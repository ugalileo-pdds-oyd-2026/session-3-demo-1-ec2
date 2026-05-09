# Session 3 — Demo 1: EC2 + Terraform Module

A minimal Go HTTP server deployed to a Graviton2 EC2 instance via a self-contained Terraform module that handles IAM, security groups, and user-data bootstrapping.

---

## What students learn

- How Go build tags (`!lambda` / `lambda`) let the same `main.go` compile to different entrypoints for different compute targets
- How to cross-compile a Go static binary for Graviton2 (linux/arm64) using `GOOS`, `GOARCH`, and `CGO_ENABLED=0`
- Why AMI IDs must be module input variables — they are region-specific and architecture-specific
- Why `allowed_cidr_blocks` has no default — forcing a deliberate security decision at call time
- The IAM resource chain EC2 requires: role → policy attachments → instance profile → `aws_instance`
- How Terraform resolves resource creation order from the reference graph, not explicit sequencing

---

## Project structure

```
.
├── app/
│   ├── go.mod
│   ├── go.sum
│   ├── main.go       # HTTP handler — identical across EC2, ECS, EKS, Lambda
│   ├── server.go     # //go:build !lambda — starts net/http server on :8080
│   └── lambda.go     # //go:build lambda — wraps handler with httpadapter
└── infra/
    ├── provider.tf
    ├── variables.tf
    ├── outputs.tf
    ├── main.tf                          # module call — wires root vars to module
    ├── envs/dev/dev.tfvars
    └── modules/
        └── compute_ec2/
            ├── variables.tf             # module inputs
            ├── outputs.tf               # instance_id, public_ip
            └── main.tf                  # all AWS resources
```

---

## Prerequisites

- Go ≥ 1.21 — `go version`
- Terraform ≥ 1.6 — `terraform -version`
- AWS CLI v2 with credentials configured — `aws sts get-caller-identity`

---

## Demo workflow

### 1. Examine the application

Open `app/main.go`, `server.go`, and `lambda.go`. `main.go` defines `buildHandler()` — it registers `/health` and `/echo` and reads `COMPUTE_TYPE` from the environment. It is identical across all four demos.

`server.go` has a `//go:build !lambda` build tag: it starts an HTTP server and is the active entrypoint for EC2, ECS, and EKS. `lambda.go` has `//go:build lambda` and is only compiled when you pass `-tags lambda`.

### 2. Compile for Graviton2 (arm64)

The instance type is `t4g.nano` — Graviton2, arm64. An x86 binary will not run on it.

```bash
cd app/
go mod tidy
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o server .
ls -lh server
```

- `GOOS=linux` — target OS is Linux
- `GOARCH=arm64` — target CPU is Graviton2; an x86 binary won't run on t4g
- `CGO_ENABLED=0` — fully static binary, no libc dependency

The result is a single ~7 MB file with no runtime to install on the instance.

### 3. Fill in `modules/compute_ec2/variables.tf`

```hcl
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
  # us-west-2, Amazon Linux 2023, arm64: ami-0ddb64e71e68cf624
}

variable "instance_type" {
  description = "EC2 instance type — must match AMI architecture (arm64 → t4g.*)"
  type        = string
  default     = "t4g.nano"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks permitted to reach port 8080 on the instance"
  type        = list(string)
}

variable "app_s3_bucket" {
  description = "S3 bucket containing the pre-compiled Go binary"
  type        = string
}
```

`ami_id` has no default because AMI IDs are both region-specific and architecture-specific — hardcoding one inside a module breaks it the moment a different region or architecture is used.

`allowed_cidr_blocks` has no default because a silent `0.0.0.0/0` default is a security risk hiding inside a module.

### 4. Add IAM resources to `modules/compute_ec2/main.tf`

EC2 cannot assume a role ARN directly. The required pattern is: create a role → attach policies → wrap it in an instance profile → reference the profile name on the instance.

```hcl
resource "aws_iam_role" "instance" {
  name = "${var.name}-${var.environment}-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "s3_read" {
  name = "read-app-binary"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::${var.app_s3_bucket}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-${var.environment}-profile"
  role = aws_iam_role.instance.name
}
```

### 5. Add the security group to `modules/compute_ec2/main.tf`

Inbound: port 8080, TCP, from `var.allowed_cidr_blocks` only. Outbound: unrestricted (needed for S3 access and `yum update`).

```hcl
resource "aws_security_group" "instance" {
  name        = "${var.name}-${var.environment}-sg"
  description = "Allow HTTP from allowed CIDRs only"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 6. Add the EC2 instance to `modules/compute_ec2/main.tf`

The `user_data` script runs as root at boot: it downloads the pre-compiled binary from S3 and starts it in the background with `nohup ... &`, which keeps the process running after user-data finishes.

```hcl
resource "aws_key_pair" "ec2_key" {
  key_name   = "${var.name}-${var.environment}-ec2-key"
  public_key = file("${path.module}/key.pub")
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.this.name
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    aws s3 cp s3://${var.app_s3_bucket}/server /opt/server
    chmod +x /opt/server
    COMPUTE_TYPE=ec2 nohup /opt/server &
  EOF
  )

  tags = {
    Name        = "${var.name}-${var.environment}-ec2-instance"
    Environment = var.environment
  }
}
```

### 7. Fill in `modules/compute_ec2/outputs.tf`

```hcl
output "instance_id" {
  description = "The ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "The public IP address of the EC2 instance."
  value       = aws_instance.this.public_ip
}
```

### 8. Wire the root module in `infra/main.tf`

The root `outputs.tf` proxies these as `compute_ec2_instance_id` and `compute_ec2_public_ip`.

```hcl
module "compute_ec2" {
  source = "./modules/compute_ec2"

  environment         = var.environment
  name                = var.name
  ami_id              = var.ami_id
  instance_type       = var.instance_type
  app_s3_bucket       = var.app_s3_bucket
  allowed_cidr_blocks = var.allowed_cidr_blocks
}
```

### 9. Initialize and apply

```bash
cd infra/
terraform init
terraform plan  -var-file=envs/dev/dev.tfvars
terraform apply -var-file=envs/dev/dev.tfvars
```

Terraform resolves the creation order from the reference graph — you describe what depends on what, not the sequence. The plan output shows: IAM role → SSM attachment → S3 policy → instance profile → security group → instance.

### 10. Verify

Allow ~30 seconds for the instance to boot, then another ~20 seconds for user-data to download and start the binary.

```bash
INSTANCE_IP=$(terraform output -raw compute_ec2_public_ip)

curl http://${INSTANCE_IP}:8080/health
```

Expected output:

```json
{"compute":"ec2","status":"ok"}
```

```bash
curl -X POST http://${INSTANCE_IP}:8080/echo \
  -H "Content-Type: application/json" \
  -d '{"message":"hello"}'
```

Expected output:

```json
{"compute":"ec2","message":"hello"}
```

These two endpoints — `/health` and `/echo` — are identical in demos 2, 3, and 4. Only the URL changes.

### 11. Clean up

```bash
terraform destroy -var-file=envs/dev/dev.tfvars
```

---

## Next steps

### GitHub Actions CD pipeline

The deployment steps above run manually. A push-to-`main` workflow can automate the full cycle: build → upload to S3 → `terraform apply`. The pipeline uses `actions/setup-go`, `aws-actions/configure-aws-credentials`, and `hashicorp/setup-terraform` — the same commands from the workflow above, sequenced as job steps.

---

## Expected outcomes

By the end of this demo, you should be able to:

1. Explain how Go build tags select different entrypoints from the same `main.go` at compile time
2. Cross-compile a fully static Go binary for a target OS and architecture using `GOOS`, `GOARCH`, and `CGO_ENABLED=0`
3. Explain why AMI IDs must be module input variables rather than hardcoded values
4. Describe the IAM chain EC2 requires: role → policy attachments → instance profile → referenced by name on the instance
5. Explain why `allowed_cidr_blocks` has no default and what the security consequence of a silent default would be
6. Read a Terraform plan and trace the resource creation order back to the reference graph
