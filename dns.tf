data "aws_route53_zone" "tradesignalserver" {
  name = "tradesignalserver.com"
}

data "aws_lb" "signals" {
  # load balancer name is the first four parts of its host name
  name = join("-", slice(split("-", kubernetes_ingress.nginx.status.0.load_balancer.0.ingress.0.hostname), 0, 4))
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.tradesignalserver.zone_id
  name    = "tradesignalserver.com"
  type    = "A"
  alias {
    name                   = data.aws_lb.signals.dns_name
    zone_id                = data.aws_lb.signals.zone_id
    evaluate_target_health = true
  }
}