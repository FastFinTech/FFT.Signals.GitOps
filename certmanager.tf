module "cert-manager" {
  source  = "sculley/cert-manager/kubernetes"
  version = "1.0.2"
}

resource "kubernetes_secret" "selfsigned-cert-tls" {
  metadata {
    name      = "selfsigned-cert-tls"
    namespace = "cert-manager"
  }
}

# resource "kubernetes_secret" "signalserver_tls" {
#   metadata {
#     name = "signalserver-tls"
#     namespace = "cert-manager"
#   }
# }

resource "kubectl_manifest" "selfsigned_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
  namespace: cert-manager
spec:
  selfSigned: {}
YAML
}

resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
  namespace: cert-manager
spec:
  acme:
    email: admin@tradesignalserver.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: signalserver-tls
    solvers:
    - http01:
        ingress:
          class: alb 
YAML
}

resource "kubectl_manifest" "selfsigned_certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-cert
  namespace: cert-manager
spec:
  dnsNames:
  - "tradesignalserver.com"
  secretName: selfsigned-cert-tls
  issuerRef:
    name: selfsigned
YAML
}

resource "kubectl_manifest" "tradesignalserver_certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: tradesignalserver-cert
  namespace: cert-manager
spec:
  dnsNames:
  - "tradesignalserver.com"
  secretName: signalserver_tls
  issuerRef:
    name: letsencrypt-staging
YAML
}

