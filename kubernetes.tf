# Equivalent to:
# kubectl create secret docker-registry my-secret --docker-server=DOCKER_REGISTRY_SERVER --docker-username=DOCKER_USER --docker-password=DOCKER_PASSWORD
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret#example-usage-docker-config
resource "kubernetes_secret" "container_registry" {
  metadata {
    name = "docker-cfg" # name of the secret as specified by "my-secret" in the command line above
  }

  data = {
    ".dockerconfigjson" = <<DOCKER
{
  "auths": {
    "${var.container_registry.host}": {
      "auth": "${base64encode("${var.container_registry.username}:${var.container_registry.password}")}"
    }
  }
}
DOCKER
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_deployment" "signalserver" {
  metadata {
    name = "signalserver"
    labels = {
      app = "signalserver"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "signalserver"
      }
    }
    template {
      metadata {
        labels = {
          app = "signalserver"
        }
      }
      spec {
        image_pull_secrets {
          name = "docker-cfg"
        }
        container {
          image = "ghcr.io/fastfintech/signalserver:latest" # 'latest' tag also sets image_pull_policy = "Always"
          name  = "signalserver"
          env {
            name  = "EventStore__ConnectionString"
            value = local.eventstore_connection_string
          }
          env {
            name  = "Redis__ConnectionString"
            value = local.redis_connection_string
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "signalserver" {
  metadata {
    name = "signalserver"
  }
  spec {
    selector = {
      app = "signalserver"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}