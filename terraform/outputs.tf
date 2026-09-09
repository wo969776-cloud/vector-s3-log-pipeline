output "vector_access_key_id" {
  value = aws_iam_access_key.vector.id
}

output "vector_secret_access_key" {
  value     = aws_iam_access_key.vector.secret
  sensitive = true
}
