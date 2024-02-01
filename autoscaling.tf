data "aws_key_pair" "key" {
  key_name = "ZYPH-Lab-Test"
}
resource "aws_security_group" "apache-sg" {
  name        = "apache-sg"
  description = "My Security Group"
  vpc_id      = aws_vpc.main.id # Set your VPC ID

  dynamic "ingress" {
    for_each = var.security_group_rules
    content {
 #     type        = ingress.value["type"]
      from_port   = ingress.value["from_port"]
      to_port     = ingress.value["to_port"]
      protocol    = ingress.value["protocol"]
      cidr_blocks = ingress.value["cidr_blocks"]
    }
  }

  dynamic "egress" {
    for_each = var.security_group_rules
    content {
 #     type        = egress.value["type"]
      from_port   = egress.value["from_port"]
      to_port     = egress.value["to_port"]
      protocol    = egress.value["protocol"]
      cidr_blocks = egress.value["cidr_blocks"]
    }
  }
}
resource "aws_launch_template" "apache-template" {
  name_prefix   = "apache-template"
  image_id      = var.ami
  instance_type = "t2.micro"
  key_name = data.aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.apache-sg.id]
}

resource "aws_autoscaling_group" "apache-asg" {
  vpc_zone_identifier = aws_subnet.private-subnet[*].id
#  target_group_arns  = [aws_lb.apache[0].arn]
  desired_capacity   = 2
  max_size           = 3
  min_size           = 2

  launch_template {
    id      = aws_launch_template.apache-template.id
    version = "$Latest"
  }
  
}
resource "aws_autoscaling_attachment" "my_asg_attachment" {
  lb_target_group_arn = aws_lb_target_group.apache-instance.arn
  autoscaling_group_name = aws_autoscaling_group.apache-asg.name
}
resource "aws_autoscaling_attachment" "my_asg_attachment443" {
  lb_target_group_arn = aws_lb_target_group.apache-instance443.arn
  autoscaling_group_name = aws_autoscaling_group.apache-asg.name
}