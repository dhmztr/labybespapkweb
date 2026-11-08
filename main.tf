provider "aws" {
  region = "eu-north-1"


# sg
resource "aws_security_group" "unter_sg" {
  name        = "unter-k3s-sg"
  description = "Ruch dla aplikacji Unter i SSH"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # wypadaloby podac nasze ip tylko
  }

  ingress {
    description = "Aplikacja (NodePort)"
    from_port   = 30080
    to_port     = 30080
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

# ec2
resource "aws_instance" "unter_server" {
  ami           = "ami-021aa12740bc00513"
  instance_type = "t3.micro"
  key_name      = "aws-klucz-laby"

  vpc_security_group_ids = [aws_security_group.unter_sg.id]

  # skrypt startowy
  user_data = <<-EOF
              #!/bin/bash
	      # 2g swapu bo malo ramu
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

              curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
              
              chmod 644 /etc/rancher/k3s/k3s.yaml
              EOF

  tags = {
    Name = "Unter-Production"
  }
}
