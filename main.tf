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
    kubernetes.io/role/elb = "1"
  }
}
resource "aws_subnet" "private-subnet" {
  count = length(var.private_subnet_cidr_blocks)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_blocks[count.index]
  availability_zone       = element(["ap-southeast-1a","ap-southeast-1b"], count.index)
  map_public_ip_on_launch = true
  tags = {
    kubernetes.io/role/elb = "1"
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
# Create security group for alb
resource "aws_security_group" "eks-alb-sg" {
  name        = "eks-alb-sg"
  description = "Security group for application load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow http user traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow user traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow everything"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


# Create Application load balancer 
resource "aws_lb" "eks-alb" {

  name               = "lab-eks-lb"
  
  
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.eks-alb-sg.id]
  subnets            = aws_subnet.public-subnet[*].id
  enable_deletion_protection = false
  depends_on = [aws_internet_gateway.internet-gateway]
}

# Create target group

resource "aws_lb_target_group" "lab-alb-tg" {
  name        = "lab-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"  // instance 
  vpc_id      = aws_vpc.main.id

  # my node app replies HTTP "200" on /health path
  health_check {
    interval            = 15
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3

    matcher = "200-499"  # Allow any HTTP status code in the range 200-499
    
  }
}

resource "aws_autoscaling_attachment" "example" {
  autoscaling_group_name = "eks-EKS_NG-14c70948-f8a9-8f05-2c28-bacc6f709ba7"
  lb_target_group_arn    = aws_lb_target_group.lab-alb-tg.arn
}
# Create listener for alb on port 80
resource "aws_lb_listener" "lab-alb-lsnr" {
  load_balancer_arn = aws_lb.eks-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab-alb-tg.arn
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


provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.eks-cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.eks-cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks_token.token
  }
}


data "aws_eks_cluster_auth" "eks_token" {
  name = aws_eks_cluster.eks-cluster.name
}

#################################

resource "aws_iam_role" "ingress-role" {
  name = "test-ingress"
  assume_role_policy = data.aws_iam_policy_document.ingress-iam.json
}

resource "aws_iam_role_policy_attachment" "ingress" {
  role = aws_iam_role.ingress-role.name
  policy_arn = aws_iam_policy.ingress.arn
}

#################################

resource "helm_release" "aws_load_balancer_controller"{
  name = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart = "aws-load-balancer-controller"
  namespace = "kube-system"

  set {
    name = "replicaCount"
    value = 2
  }

  set{
    name = "clusterName"
    value = aws_eks_cluster.eks-cluster.name
  }

  set{
    name="vpcId"
    value = aws_vpc.main.id
  }

  set{
    name = "serviceAccount.name"
    value= "aws-load-balancer-controller"
  }

  set{
    name= "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.ingress-role.arn
  }
}
###############################################

data "tls_certificate" "eks"{
 url = aws_eks_cluster.eks-cluster.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.eks-cluster.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

# LB-role.tf
data "aws_iam_policy_document" "ingress-iam" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect = "Allow"

    condition {
      test ="StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
  }
}



###############################

# ALB IAM POLICY
resource "aws_iam_policy" "ingress" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "AWS Load Balancer Controller IAM Policy"
  policy    = jsonencode(
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "StringEquals": {
                    "elasticloadbalancing:CreateAction": [
                        "CreateTargetGroup",
                        "CreateLoadBalancer"
                    ]
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule"
            ],
            "Resource": "*"
        }
    ]
})
}


