provider "aws" {
  region = "eu-north-1"
}


# najnowsze ami ubuntu 26.04 bo recznie marudzilo
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-26.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}



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
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = "aws-klucz-laby"


  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

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
