resource "aws_vpc" "main" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"
  enable_dns_hostnames = "true"
  enable_dns_support   = "true"
  tags = {
    Name = "apache-vpc"                  #Naming for VPC
  }
}
resource "aws_subnet" "public-subnet" {
  count = length(var.public_subnet_cidr_blocks)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  availability_zone       = element(["ap-southeast-1a","ap-southeast-1b"], count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "Public-Subnet-${count.index + 1}"
  }
}
resource "aws_subnet" "private-subnet" {
  count = length(var.private_subnet_cidr_blocks)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_blocks[count.index]
  availability_zone       = element(["ap-southeast-1a","ap-southeast-1b"], count.index)
  map_public_ip_on_launch = false
  tags = {
    Name = "Private-Subnet-${count.index + 1}"
  }
}
resource "aws_internet_gateway" "internet-gateway" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "apache-igw"
  }
}
#Create route table for public subnets
resource "aws_route_table" "public-rtb" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }

  tags = {
    Name = "apache_public_rtb"
    Tier = "public"
  }
}
resource "aws_route_table" "private-rtb" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "apache_public_rtb"
    Tier = "public"
  }
}
resource "aws_route_table_association" "public" {
   depends_on     = [aws_subnet.public-subnet]
   route_table_id = aws_route_table.public-rtb.id
   subnet_id      = aws_subnet.public-subnet[count.index].id 
   count          = length(var.public_subnet_cidr_blocks)
 }
  resource "aws_route_table_association" "private" {
    depends_on     = [aws_subnet.private-subnet]
    route_table_id = aws_route_table.private-rtb.id
    count          = length(var.private_subnet_cidr_blocks)
    subnet_id      = aws_subnet.private-subnet[count.index].id  
}