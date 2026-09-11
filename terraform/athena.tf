# Glue 데이터베이스 — Athena가 테이블을 담는 논리적 그릇
resource "aws_glue_catalog_database" "logs" {
  name = "log_pipeline_db"
}

# Glue 테이블 — S3의 NDJSON 로그에 스키마를 얹음 (외부 테이블)
resource "aws_glue_catalog_table" "logs" {
  name          = "logs"
  database_name = aws_glue_catalog_database.logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"            = "json"
    "projection.enabled"        = "true"

    "projection.year.type"      = "integer"
    "projection.year.range"     = "2026,2027"
    "projection.year.digits"    = "4"

    "projection.month.type"     = "integer"
    "projection.month.range"    = "01,12"
    "projection.month.digits"   = "2"

    "projection.day.type"       = "integer"
    "projection.day.range"      = "01,31"
    "projection.day.digits"     = "2"

    "projection.hour.type"      = "integer"
    "projection.hour.range"     = "00,23"
    "projection.hour.digits"    = "2"

    "storage.location.template" = "s3://${aws_s3_bucket.logs.bucket}/logs/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.logs.bucket}/logs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "ts"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "service"
      type = "string"
    }
    columns {
      name = "pod"
      type = "string"
    }
    columns {
      name = "node"
      type = "string"
    }
    columns {
      name = "level"
      type = "string"
    }
    columns {
      name = "logger"
      type = "string"
    }
    columns {
      name = "thread"
      type = "string"
    }
    columns {
      name = "exception"
      type = "string"
    }
    columns {
      name = "is_error"
      type = "boolean"
    }
    columns {
      name = "message"
      type = "string"
    }
  }
}

# Athena Workgroup — 쿼리 결과 저장 위치를 코드로 선언 (IaC)
resource "aws_athena_workgroup" "logs" {
  name = "log_pipeline_wg"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.logs.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  force_destroy = true
}
