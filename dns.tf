resource "aws_route53_zone" "signals" {
  name = "tradesignalserver.com"
}

# resource "aws_route53_record" "www" {
#   description = "A record for tradesignalserver.com. Currently serving as alias for the aws EKS loadbalancer in the 'signals' vpc."
#   zone_id = aws_route53_zone.signals.zone_id
#   name    = "tradesignalserver.com"
#   type    = "A"
#   alias {
#     name                   = data.aws_elb.signals.dns_name
#     zone_id                = data.aws_elb.signals.zone_id
#     evaluate_target_health = true
#   }
# }