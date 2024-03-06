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
  map_public_ip_on_launch = true
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
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }

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

# EKS Cluster role
resource "aws_iam_role" "eks-cluster-role" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "eks.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }   
  )
}

resource "aws_iam_role_policy_attachment" "eks-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster-role.name
}
resource "aws_iam_role_policy_attachment" "eks-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks-cluster-role.name
}

# EKS Node Group role

resource "aws_iam_role" "eks-cluster-ng-role" {
  name = "eks-cluster-ng-role"
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }],
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks-cluster-ng-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-cluster-ng-role.name
}

resource "aws_iam_role_policy_attachment" "eks-cluster-ng-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-cluster-ng-role.name
}

resource "aws_iam_role_policy_attachment" "eks-cluster-ng-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-cluster-ng-role.name
}

# Security Group for EKS cluster

resource "aws_security_group" "eks-cluster-sg" {
  name        = "eks-cluster-sg"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  // Ingress rule allowing traffic from the VPC CIDR
  ingress {
    from_port   = 0    # Adjust the source port if needed
    to_port     = 0    # Adjust the destination port if needed
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["10.0.0.0/16"]
  }
  
}


# Security Group for EKS nodes

resource "aws_security_group" "eks-ng-sg" {
  name        = "eks-ng-sg"
  description = "Internal VPC - Nodes communication"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Ingress rule allowing traffic from the VPC CIDR
  ingress {
    from_port   = 0    # Adjust the source port if needed
    to_port     = 0    # Adjust the destination port if needed
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["10.0.0.0/16"]
  }
}

# EKS Cluster

resource "aws_eks_cluster" "eks-cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks-cluster-role.arn
  
  
  vpc_config {
    security_group_ids      = [aws_security_group.eks-cluster-sg.id]
    subnet_ids              = aws_subnet.private-subnet[*].id
    endpoint_private_access = "true"
    endpoint_public_access  = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks-cluster-AmazonEKSServicePolicy,
  ]

}



# EKS Node Group

resource "aws_eks_node_group" "eks-cluster-ng" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "EKS_NG"
  node_role_arn   = aws_iam_role.eks-cluster-ng-role.arn
  subnet_ids      = aws_subnet.private-subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }
  ami_type       = "AL2_x86_64"
  instance_types = ["t2.medium"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20
  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-ng-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-cluster-ng-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-cluster-ng-AmazonEC2ContainerRegistryReadOnly,
  ]

  lifecycle {
    create_before_destroy = true
  }
}


#############
# Addon EKS #
#############
# Data block to fetch EKS cluster information

 
data "aws_eks_cluster" "eks_cluster_info" {
  name = aws_eks_cluster.eks-cluster.name
}


module "eks_blueprints_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version
  

  cluster_name      = aws_eks_cluster.eks-cluster.name
  
  cluster_endpoint  = data.aws_eks_cluster.eks_cluster_info.endpoint
  cluster_version   = data.aws_eks_cluster.eks_cluster_info.version
  oidc_provider_arn = data.aws_eks_cluster.eks_cluster_info.identity[0].oidc[0].issuer
  

  eks_addons = {
  /*
    aws-ebs-csi-driver = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  
  */
  
    // do this first
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }
}