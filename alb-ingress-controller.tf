# Create a test deployment
resource "kubernetes_deployment" "nginx" {
  metadata {
    name = "nginx"
    labels = {
      app = "nginx"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.20.2"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

# Create service for the test deployment
resource "kubernetes_service" "nginx" {
  metadata {
    name = "nginx"
    labels = {
      app = "nginx"
    }
  }
  spec {
    type = "NodePort" # Makes the service available to the AWS Load Balancer
    selector = {
      app = "nginx"
    }
    port {
      port        = 80
      target_port = 80
      # leave node_port blank to allow kubernetes to allocate any unused node_port value
    }
  }
}

# Adds the aws load balancer controller to kubernetes
module "eks-lb-controller" {
  source                           = "DNXLabs/eks-lb-controller/aws"
  version                          = "0.5.0"
  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url # module.eks exists in main.tf
  cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn
  cluster_name                     = module.eks.cluster_id
}

resource "kubernetes_ingress" "nginx" {
  metadata {
    name = "nginx-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "alb" # use the aws load balancer
      "alb.ingress.kubernetes.io/scheme" = "internet-facing" # make the load balancer public
    }
  }
  spec {
    rule {
      http {
        path {
          path = "/"
          backend {
            service_name = kubernetes_service.nginx.metadata.0.name
            service_port = kubernetes_service.nginx.spec.0.port.0.node_port # have also tried "80" 
          }
        }
      }
    }
  }
}

