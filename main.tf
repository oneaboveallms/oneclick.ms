# Specify the Terraform provider
provider "aws" {
  region = "us-east-2"
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/20"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "assignment4-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count                   = 1
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(["10.0.0.0/22", "10.0.4.0/22"], count.index)
  availability_zone       = element(["us-east-2a", "us-east-2b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(["10.0.8.0/22", "10.0.12.0/22"], count.index)
  availability_zone = element(["us-east-2a", "us-east-2b"], count.index)

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "assignment4-igw"
  }
}

# NAT Gateway
resource "aws_eip" "nat" {
  count = 1

  tags = {
    Name = "assignment4-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "assignment4-nat-gateway"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "assignment4-public-route-table"
  }
}

# Public Route Table Association
resource "aws_route_table_association" "public" {
  count          = 1
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "assignment4-private-route-table"
  }
}

# Private Route Table Association
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for Bastion Host
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.main.id

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

  tags = {
    Name = "bastion-sg"
  }
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami           = "ami-074b5fedd63e481ec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name      = "ohio2"

  tags = {
    Name = "bastion-host"
  }
}

# Security Group for nginx Servers
resource "aws_security_group" "zabbix_sg" {
  vpc_id = aws_vpc.main.id


  ingress {
    from_port   = 10051
    to_port     = 10051
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zabbix-sg"
  }
}

# nginx Application Server
resource "aws_instance" "zabbix_server" {
  ami           = "ami-074b5fedd63e481ec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]
  key_name      = "ohio2"

  tags = {
    Name = "zabbix-server"
  }
}

# Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nginx_sg.id]
  subnets            = aws_subnet.private_subnets[*].id

  tags = {
    Name = "assignment4-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name        = "app-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  tags = {
    Name = "assignment4-tg"
  }
}

# Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "app_lt" {
  name          = "app-launch-template"
  image_id      = "ami-074b5fedd63e481ec"
  instance_type = "t2.micro"
  key_name      = "ohio2"

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.nginx_sg.id]
    subnet_id                   = aws_subnet.private_subnets[0].id
  }

  tags = {
    Name = "assignment4-launch-template"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = aws_subnet.private_subnets[*].id
  desired_capacity    = 2
  max_size            = 2
  min_size            = 1
  
}

# VPC Peering
resource "aws_vpc_peering_connection" "vpc_peering" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = "vpc-08bd5ac0c9b883f3e" # Replace with your Default VPC ID

  tags = {
    Name = "assignment4-vpc-peering"
  }
}

resource "aws_vpc_peering_connection_accepter" "vpc_peering_accepter" {
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
  auto_accept               = true

  tags = {
    Name = "assignment4-vpc-peering-accepter"
  }
}

# Route from Custom VPC to Default VPC
resource "aws_route" "custom_to_default" {
  route_table_id         = aws_route_table.private.id # Replace with appropriate route table
  destination_cidr_block = "172.31.0.0/16" # Replace with Default VPC CIDR block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

# Route from Default VPC to Custom VPC
resource "aws_route" "default_to_custom" {
  route_table_id         = "rtb-0a787d8cc46365d83" # Replace with Default VPC Route Table ID
  destination_cidr_block = aws_vpc.main.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

output "vpc_peering_connection_id" {
  value = aws_vpc_peering_connection.vpc_peering.id
}

