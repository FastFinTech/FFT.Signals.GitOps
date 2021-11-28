resource "kubernetes_ingress" "nginx" {
  metadata {
    name = "nginx-ingress"
    annotations = {
      "kubernetes.io/ingress.class"      = "alb"             # use the aws load balancer
      "alb.ingress.kubernetes.io/scheme" = "internet-facing" # make the load balancer public
      "cert-manager.io/cluster-issuer"   = "letsencrypt-staging"
    }
  }
  spec {
    tls {
      hosts       = ["tradesignalserver.com"]
      secret_name = "signalserver-tls"
    }
    backend {
      service_name = kubernetes_service.signalserver.metadata.0.name
      service_port = kubernetes_service.signalserver.spec.0.port.0.port
    }
    # rule {
    #   host = "tradesignalserver.com"
    #   http {
    #     path {
    #       path = "/"
    #       backend {
    #         service_name = kubernetes_service.nginx.metadata.0.name
    #         service_port = kubernetes_service.nginx.spec.0.port.0.port
    #       }
    #     }
    #   }
    # }
  }
}

# resource "kubernetes_ingress" "signalserver" {
#   metadata {
#     name = "signalserver-ingress"
#     annotations = {
#       "kubernetes.io/ingress.class" = "alb"
#       #"alb.ingress.kubernetes.io/group.name" = "my-group" # to share an alb with multiple ingressess
#     }
#   }
#   spec {
#     backend {
#       service_name = kubernetes_service.signalserver.metadata.0.name
#       service_port = kubernetes_service.signalserver.spec.0.port.0.port
#     }
#     rule {
#       host = "tradesignalserver.com"
#       http {
#         path {
#           path = "/"
#           backend {
#             service_name = kubernetes_service.signalserver.metadata.0.name
#             service_port = kubernetes_service.signalserver.spec.0.port.0.port
#           }
#         }
#       }
#     }
#   }
# }