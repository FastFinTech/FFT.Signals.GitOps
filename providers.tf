provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
    host                   = data.aws_eks_cluster.signals.endpoint
    token                  = data.aws_eks_cluster_auth.signals.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
}

provider "eventstorecloud" {
  token           = "lruR-CmmEI5lBu-AGHJLCBQsYalkIwkvfVbAjg3rLVkaL"
  organization_id = "c2iaa6do0aem35kk66t0" # FFT.Signals
}
