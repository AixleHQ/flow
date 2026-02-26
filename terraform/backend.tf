terraform {
  backend "s3" {
    bucket         = "palad-tfstate"  # Change to your actual bucket name
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    # dynamodb_table = "terraform-locks"  # Optional: uncomment after creating DynamoDB table for state locking
  }
}
