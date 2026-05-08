resource "aws_security_group" "ec2_sg" {
  name        = "${var.environment}-ec2-sg"
  description = "Security group for EC2 instances"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "${var.environment}-ec2-key"
  public_key = file("${path.module}/key.pub")
}

resource "aws_instance" "ec2_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.ec2_key.key_name

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name        = "${var.environment}-ec2-instance"
    Environment = var.environment
  }
}
