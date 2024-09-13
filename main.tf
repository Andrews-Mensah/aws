provider "aws" {
    region = "us-east-1"
  }
  
  # Create a VPC
  resource "aws_vpc" "andrews_assignment" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
  }
  
  # Create a public subnet
  resource "aws_subnet" "public" {
    vpc_id            = aws_vpc.andrews_assignment.id
    cidr_block        = "10.0.1.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
  }
  
  # Create a private subnet
  resource "aws_subnet" "private" {
    vpc_id            = aws_vpc.andrews_assignment.id
    cidr_block        = "10.0.2.0/24"
    availability_zone = "us-east-1a"
  }
  
  # Internet Gateway for public subnet
  resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.andrews_assignment.id
  }
  
  # Public route table
  resource "aws_route_table" "public" {
    vpc_id = aws_vpc.andrews_assignment.id
  }
  
  # Route for the internet gateway in the public subnet
  resource "aws_route" "public_internet_access" {
    route_table_id         = aws_route_table.public.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id             = aws_internet_gateway.igw.id
  }
  
  # Associate route table with public subnet
  resource "aws_route_table_association" "public_assoc" {
    subnet_id      = aws_subnet.public.id
    route_table_id = aws_route_table.public.id
  }
  
  # Create security group for EC2 instance allowing SSH and DB connection
  resource "aws_security_group" "ec2_sg" {
    vpc_id = aws_vpc.andrews_assignment.id
  
    ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  
    ingress {
      from_port   = 5432 # PostgreSQL port
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [aws_vpc.andrews_assignment.cidr_block]
    }
  
    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  # Create security group for RDS allowing only EC2 instance access
  resource "aws_security_group" "rds_sg" {
    vpc_id = aws_vpc.andrews_assignment.id
  
    ingress {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      security_groups = [aws_security_group.ec2_sg.id]
    }
  
    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  # RDS Subnet Group for the private subnet
  resource "aws_db_subnet_group" "rds_subnet_group" {
    name       = "rds-subnet-group"
    subnet_ids = [aws_subnet.private.id]
  }
  
  # Create RDS instance in the private subnet
  resource "aws_db_instance" "rds_instance" {
    allocated_storage    = 20
    engine               = "postgres"
    engine_version       = "13.4"
    instance_class       = "db.t2.micro"
    name                 = "mydatabase"
    username             = "admin"
    password             = "password123"
    db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
    vpc_security_group_ids = [aws_security_group.rds_sg.id]
    publicly_accessible  = false
  }
  
  # Create IAM Role for EC2 to interact with RDS
  resource "aws_iam_role" "ec2_role" {
    name = "ec2_rds_role"
  
    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
        }
      ]
    })
  }
  
  # Attach policy allowing EC2 to connect to RDS
  resource "aws_iam_role_policy" "ec2_rds_policy" {
    role = aws_iam_role.ec2_role.id
  
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = "rds-db:connect"
          Effect = "Allow"
          Resource = "*"
        }
      ]
    })
  }
  
  # Create Instance Profile for EC2
  resource "aws_iam_instance_profile" "ec2_profile" {
    name = "ec2_rds_profile"
    role = aws_iam_role.ec2_role.id
  }
  
  # Create EC2 instance in the public subnet
  resource "aws_instance" "ec2_instance" {
    ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
    instance_type = "t2.micro"
    subnet_id     = aws_subnet.public.id
    security_groups = [aws_security_group.ec2_sg.id]
  
    iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  
    user_data = <<-EOF
      #!/bin/bash
      sudo yum install -y postgresql
      psql -h ${aws_db_instance.rds_instance.address} -U admin -d mydatabase -c "SELECT 1;"
    EOF
  }
  
  # Output EC2 public IP for SSH access
  output "ec2_public_ip" {
    value = aws_instance.ec2_instance.public_ip
  }
  
  # Output RDS endpoint for connection details
  output "rds_endpoint" {
    value = aws_db_instance.rds_instance.address
  }
  