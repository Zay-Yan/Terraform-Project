terraform {
  backend "s3" {
    bucket         = "apache-bucket-zy"
    key            = "terraform.tfstate"  # Replace with a unique key for each configuration
    region         = "ap-southeast-1"
    encrypt        = true
    acl            = "private"
    #dynamodb_table = "terraform-lock"  # Optional: Use DynamoDB for state locking
  }
}