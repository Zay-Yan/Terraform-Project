resource "aws_s3_bucket" "apache_logs" {
  bucket = "apache-bucket-zy"
  tags = {
    Name        = "apache-bucket"
  }
}
resource "aws_security_group" "apache-lb-sg" {
  name        = "apache-lb-sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.apache_logs.bucket

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_policy" "elb_access_logs_policy" {
#  depends_on = [ aws_lb.apache ]
  bucket = aws_s3_bucket.apache_logs.bucket

  policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::114774131450:root"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::apache-bucket-zy/apache-lb/AWSLogs/896836667748/*"
    }
  ]
})
}

resource "aws_lb" "apache" {
  name               = "apache-lb"
  depends_on         = [ aws_subnet.public-subnet ]
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.apache-lb-sg.id]
  subnets            = [for subnet in aws_subnet.public-subnet : subnet.id]
  count              = length(var.public_subnet_cidr_blocks)

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.apache_logs.id
    prefix  = "apache-lb"
    enabled = true
  }

  tags = {
    Environment = "production"
  }
}
resource "aws_lb_target_group" "apache-instance" {
  name     = "apache-instance-80"
  port     = 80
  protocol = "HTTP"
  target_type = "instance"
  vpc_id   = aws_vpc.main.id
}
resource "aws_lb_target_group" "apache-instance443" {
  name     = "apache-instance-443"
  port     = 443
  protocol = "HTTPS"
  target_type = "instance"
  vpc_id   = aws_vpc.main.id
}
resource "aws_lb_listener" "apache-lb-80" {
  count = length(aws_lb.apache)
  load_balancer_arn = aws_lb.apache[count.index].arn
  port              = "80"
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apache-instance.arn
  }
}
resource "aws_lb_listener" "apache-lb-443" {
  count = length(aws_lb.apache)
  load_balancer_arn = aws_lb.apache[count.index].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:ap-southeast-1:896836667748:certificate/31e9d408-5919-4cc4-b69e-2c1129b177e2"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apache-instance443.arn
  }
}
