locals {
  host                    = "tradesignalserver.com"
  certificate_secret_name = "tradesignalserver-tls"
  issuer_name             = "letsencrypt"
}

# Adds the aws load balancer controller to kubernetes
module "eks-lb-controller" {
  source                           = "DNXLabs/eks-lb-controller/aws"
  version                          = "0.5.0"
  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn
  cluster_name                     = module.eks.cluster_id
}

module "cert-manager" {
  source  = "DNXLabs/eks-cert-manager/aws"
  version = "0.3.3"

  cluster_name                     = module.eks.cluster_id
  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn

  http01 = [
    {
      name           = local.issuer_name
      kind           = "ClusterIssuer"
      ingress_class  = "alb"
      secret_key_ref = "letsencrypt"
      acme_server    = "https://acme-v02.api.letsencrypt.org/directory"
      acme_email     = "admin@tradesignalserver.com"
    }
  ]

  certificates = [
    {
      name        = "tradesignalserver"
      namespace   = "default"
      kind        = "ClusterIssuer"
      secret_name = local.certificate_secret_name
      issuer_ref  = local.issuer_name
      dns_name    = local.host
    }
  ]
}

resource "kubernetes_ingress" "nginx" {
  metadata {
    name = "nginx-ingress"
    annotations = {
      "kubernetes.io/ingress.class"      = "alb"             # use the aws load balancer
      "alb.ingress.kubernetes.io/scheme" = "internet-facing" # make the load balancer public
      "kubernetes.io/tls-acme"           = "true"            # makes the cert-manager http solver use this ingress
      "cert-manager.io/cluster-issuer"   = local.issuer_name
    }
    labels = {
      "app" = "signalserver"
    }
  }
  spec {
    tls {
      host = local.host
      http {
        path {
          path = "/"
          backend {
            service_name = kubernetes_service.signalserver.metadata.0.name
            service_port = kubernetes_service.signalserver.spec.0.port.0.port
          }
        }
      }
    }
  }
}
