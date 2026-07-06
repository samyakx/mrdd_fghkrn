# ---------------------------------------------------------
# ROUTE 53 HOSTED ZONE
# ---------------------------------------------------------
resource "aws_route53_zone" "main" {
  name = "testmrdd.kamikazian.com"
}

# ---------------------------------------------------------
# PRIMARY REGION (ap-south-1)
# ---------------------------------------------------------
resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  # Renamed to exactly match the domain so S3 accepts the Host header!
  bucket        = "www.testmrdd.kamikazian.com"
  force_destroy = true # Ensures easy cleanup for close-to-zero bill
}

resource "aws_s3_bucket_website_configuration" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.primary.arn}/*"
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.primary]
}

resource "aws_s3_object" "primary_index" {
  provider     = aws.primary
  bucket       = aws_s3_bucket.primary.id
  key          = "index.html"
  source       = "../primary/index.html"
  content_type = "text/html"
  etag         = filemd5("../primary/index.html")
}

# ---------------------------------------------------------
# SECONDARY REGION (ap-southeast-1)
# ---------------------------------------------------------
resource "aws_s3_bucket" "secondary" {
  provider      = aws.secondary
  bucket        = "testmrdd.kamikazian.com-secondary"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.secondary.arn}/*"
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.secondary]
}

resource "aws_s3_object" "secondary_index" {
  provider     = aws.secondary
  bucket       = aws_s3_bucket.secondary.id
  key          = "index.html"
  source       = "../secondary/index.html"
  content_type = "text/html"
  etag         = filemd5("../secondary/index.html")
}

# ---------------------------------------------------------
# ROUTE 53 HEALTH CHECK & FAILOVER ROUTING
# ---------------------------------------------------------

# Health check monitoring the primary bucket
resource "aws_route53_health_check" "primary_hc" {
  fqdn              = aws_s3_bucket_website_configuration.primary.website_endpoint
  port              = 80
  type              = "HTTP"
  resource_path     = "/index.html"
  failure_threshold = "3"
  request_interval  = "30" # Note: Fast health checks cost ~$1.00/month if left running.

  tags = {
    Name = "primary-s3-health-check"
  }
}



resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.testmrdd.kamikazian.com"
  type    = "CNAME"
  ttl     = 60
  
  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "PrimaryS3"
  health_check_id = aws_route53_health_check.primary_hc.id
  records         = [aws_s3_bucket_website_configuration.primary.website_endpoint]
}

resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.testmrdd.kamikazian.com"
  type    = "CNAME"
  ttl     = 60
  
  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "SecondaryS3"
  records        = [aws_s3_bucket_website_configuration.secondary.website_endpoint]
}

# Output the Name Servers to configure in Namecheap
output "route53_name_servers" {
  description = "CRITICAL: Log into Namecheap and add these NS records for your subdomain."
  value       = aws_route53_zone.main.name_servers
}
