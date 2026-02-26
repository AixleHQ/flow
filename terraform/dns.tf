resource "aws_route53_zone" "palad_ai" {
  name = "palad.ai"

  tags = {
    Name = "palad-ai-zone"
  }
}
