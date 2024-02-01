resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "cpu-utilization-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.apache-asg.name
  }

  alarm_actions = [aws_autoscaling_policy.apache-cpu-policy.arn]
}
resource "aws_autoscaling_policy" "apache-cpu-policy" {
  name                   = "scale_up_policy"
  scaling_adjustment   = 1
  adjustment_type      = "ChangeInCapacity"
  cooldown              = 300

  autoscaling_group_name = aws_autoscaling_group.apache-asg.name
}
resource "aws_autoscaling_notification" "apache_asg_notifications" {
  group_names = [
    aws_autoscaling_group.apache-asg.name
    ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.apache.arn
}

resource "aws_sns_topic" "apache" {
  name = "apache-topic"
}