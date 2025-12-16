output "data_bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "ec2_public_ip" {
  value = aws_instance.node.public_ip
}
