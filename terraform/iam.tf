# 1. Vector 전용 IAM 사용자
resource "aws_iam_user" "vector" {
  name = "iam_jaeyeong_log"
}

# 2. 액세스 키 (K8s Secret으로 주입할 값)
resource "aws_iam_access_key" "vector" {
  user = aws_iam_user.vector.name
}

# 3. 최소권한 정책 — 이 버킷에 PutObject만
resource "aws_iam_user_policy" "vector_s3_put" {
  name = "vector-s3-put-only"
  user = aws_iam_user.vector.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPutObjectToLogBucket"
        Effect = "Allow"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/*"
      }
    ]
  })
}
