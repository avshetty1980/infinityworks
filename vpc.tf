variable "aws_access_key" {}
variable "aws_secret_key" {}

variable "ssh_key" {}

#variable "private_key_path" {}
variable "region" {
  default = "eu-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

provider "aws" {  
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region = var.region
}
resource "tls_private_key" "web_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.ssh_key
  public_key = tls_private_key.web_key.public_key_openssh
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name      = "test-vpc"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name      = "subnet_1"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name      = "subnet_2"
    ManagedBy = "terraform"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name      = "test-igw"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name      = "route-table"
    ManagedBy = "terraform"
  }
}

resource "aws_route" "route_to_gateway" {
  route_table_id         = aws_route_table.rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  depends_on             = [aws_route_table.rt]
}

resource "aws_route_table_association" "subnet_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "web_server" {
  name        = "web_server"
  description = "Allow standard HTTP, HTTPS, SSH and everything out"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_instance" "web" {
  count = 2

  ami           = "ami-403e2524"
  instance_type = "t2.micro" 
  monitoring    = false      
  user_data     = "#!/bin/bash\nyum update -y\nyum install -y httpd24\nservice httpd start"
  subnet_id     = aws_subnet.subnet_1.id
  key_name      = aws_key_pair.generated_key.key_name #var.ssh_key

  vpc_security_group_ids = [
    aws_security_group.web_server.id,
  ]

  # connection {
  #   type = "ssh"
  #   host = self.public_ip
  #   user = "ec2-user"
  #   private_key = file(var.private_key_path)
  # }

  tags = {
    Name = "web"
  }
}

# to help with attach/de-attach of eip with instances without 
# depending on it
resource "aws_eip_association" "web_eip_assoc" {
  instance_id   = aws_instance.web.0.id
  allocation_id = aws_eip.web_eip.id
}

resource "aws_eip" "web_eip" {
  instance = aws_instance.web.0.id

  tags = {
    Name      = "eip"
    ManagedBy = "terraform"
  }
}

resource "aws_elb" "clb" {
  name = "clb"
  instances = aws_instance.web[*].id
  subnets = [ aws_subnet.subnet_1.id, aws_subnet.subnet_2.id ]
  security_groups = [ aws_security_group.web_server.id ]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  tags = {
    Name      = "clb"
    ManagedBy = "terraform"
  }

}

# data "aws_availability_zone" "available" {
#   state = "available"
# }

output "instance_dns" {
  value = aws_instance.web[*].public_dns
}

output "clb_dns" {
  value = aws_elb.clb.dns_name
}
