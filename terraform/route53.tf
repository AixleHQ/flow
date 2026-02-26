# Create Route53 A record for palad.ai pointing to the k3s instance
resource "aws_route53_record" "palad_ai_root" {
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = "palad.ai"
  type    = "A"
  ttl     = 300
  records = [aws_eip.k3s.public_ip]
}

# Optional: Create wildcard subdomain record for future services
resource "aws_route53_record" "palad_ai_wildcard" {
  zone_id = aws_route53_zone.palad_ai.zone_id
  name    = "*.palad.ai"
  type    = "A"
  ttl     = 300
  records = [aws_eip.k3s.public_ip]
}
