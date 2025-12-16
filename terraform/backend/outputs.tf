output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "dynamodb_lock_table" {
  value = aws_dynamodb_table.lock.name
}

output "aws_region" {
  value = var.aws_region
}
