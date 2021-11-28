resource "kubernetes_secret" "ghcr" {
  type = "kubernetes.io/dockerconfigjson"
  metadata {
    name = "ghcr" # name of the secret as specified by "my-secret" in the command line above
  }

  data = {
    ".dockerconfigjson" = <<DOCKER
{
  "auths": {
    "ghcr.io": {
      "auth":"${base64encode("${var.ghcr_username}:${var.ghcr_token}")}"
    }
  }
}
DOCKER
  }
}