variable "vpc_cidr_block" {
  default = "10.11.0.0/16"
}

variable "public_subnet_cidr_blocks" {
 # type = string(list)
  default = ["10.11.1.0/27","10.11.2.0/27"]
}
variable "private_subnet_cidr_blocks" {
  default = ["10.11.3.0/27","10.11.4.0/27"]
}
variable "ami" {
  default = "ami-031221d6169ad9247"
}
variable "security_group_rules" {
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    {
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    },
  ]
}
variable "cluster_name" {
  default = "eks-cluster"
}
