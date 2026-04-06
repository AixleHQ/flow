resource "aws_route53_zone" "palad_ai" {
  name = "palad.ai"

  tags = {
    Name = "palad-ai-zone"
  }
}

resource "aws_route53_zone" "aixle_com" {
  name = "aixle.com"

  tags = {
    Name = "aixle-com-zone"
  }
}
