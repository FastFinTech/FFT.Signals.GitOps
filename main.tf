terraform {
  required_version = "1.0.11"
  required_providers {
    aws = {
      version = "3.63.0"
    }
    kubernetes = {
      version = "2.6.1"
    }
    eventstorecloud = {
      source  = "EventStore/eventstorecloud"
      version = "~>1.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.4.1"
    }
  }
  backend "remote" {
    organization = "FastFinTech"
    workspaces {
      name = "fft-signals"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  #alias = "eks"
  host                   = data.aws_eks_cluster.signals.endpoint
  token                  = data.aws_eks_cluster_auth.signals.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
}

provider "helm" {
  kubernetes {
    host = data.aws_eks_cluster.signals.endpoint
    # client_certificate = 
    # client_key = 
    #    config_path = "~/.kube/config"
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
    # TODO: See if this token setting will work so we can get rid of the exec.
    #token                  = data.aws_eks_cluster_auth.signals.token
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
      command     = "aws"
    }
  }
}

provider "eventstorecloud" {
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_eks_cluster" "signals" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "signals" {
  name = local.cluster_name
}

locals {
  cluster_name         = "signals"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  num_subnets          = min(length(local.public_subnet_cidrs), length(data.aws_availability_zones.available.names))
  # public_subnet_ids       = aws_subnet.signals_public.*.id
  # private_subnet_ids      = aws_subnet.signals_private.*.id
  # public_route_table_ids  = aws_route_table.signals_public.*.id
  # private_route_table_ids = aws_route_table.signals_private.*.id
  # redis_connection_string = "${aws_elasticache_cluster.signals.cache_nodes.0.address}:6379"
  redis_connection_string      = "${module.redis.elasticache_replication_group_primary_endpoint_address}:6379"
  eventstore_connection_string = "esdb://${eventstorecloud_managed_cluster.signals.dns_name}:2113"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name                 = "signals-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = local.private_subnet_cidrs
  public_subnets       = local.public_subnet_cidrs
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "redis" {
  source  = "umotif-public/elasticache-redis/aws"
  version = "~> 2.1.0"

  name_prefix           = "signals"
  number_cache_clusters = 1
  node_type             = "cache.t3.small"

  engine_version           = "6.x"
  port                     = 6379
  maintenance_window       = "mon:03:00-mon:04:00"
  snapshot_window          = "04:00-06:00"
  snapshot_retention_limit = 7

  # automatic_failover_enabled = true
  at_rest_encryption_enabled = false
  transit_encryption_enabled = false
  # auth_token                 = "1234567890asdfghjkl"

  apply_immediately = true
  family            = "redis6.x"
  description       = "Signals elasticache redis."

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]

  parameter = [
    {
      name  = "repl-backlog-size"
      value = "16384"
    }
  ]

  tags = {
  }
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  vpc_id          = module.vpc.vpc_id
  cluster_name    = local.cluster_name
  cluster_version = "1.20"
  subnets         = module.vpc.public_subnets # TODO: change back to private
  enable_irsa     = true
  tags = {
  }


  workers_group_defaults = {
    root_volume_type = "gp2"
    public_ip        = true                      # TODO: remove
    subnets          = module.vpc.public_subnets # TODO: remove
  }

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 2
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
      public_ip                     = true                      # TODO: remove
      subnets                       = module.vpc.public_subnets # TODO: remove
    }
  ]
}

# # Install an AWS ALB load balancer controller to handle ingresses with class "kubernetes.io/ingress.class" = "alb"
# module "eks-lb-controller" {
#   source                           = "DNXLabs/eks-lb-controller/aws"
#   version                          = "0.5.0"
#   cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
#   cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn
#   cluster_name                     = module.eks.cluster_id
#   depends_on                       = [module.eks]
# }

# # Almost worked, but created an internal load balancer
# module "alb_ingress_controller" {
#   source  = "iplabs/alb-ingress-controller/kubernetes"
#   version = "3.4.0"

#   # providers = {
#   #   kubernetes = "eks"
#   # }

#   k8s_cluster_type = "eks"
#   k8s_namespace    = "kube-system"

#   aws_region_name  = var.aws_region
#   k8s_cluster_name = data.aws_eks_cluster.signals.name
# }

# # Seems out of date
# module "alb-ingress" { # https://registry.terraform.io/modules/pbar1/alb-ingress/kubernetes/latest
#   source        = "pbar1/alb-ingress/kubernetes"
#   version       = "1.0.0"
#   region        = var.aws_region
#   vpc_id        = module.vpc.vpc_id
#   cluster_name  = local.cluster_name
#   namespace     = "default"
#   ingress_class = "alb" # Ingress class name to respect for the annotation kubernetes.io/ingress.class:
# }


# module "eks-alb-ingress" { # does not support recent terraform versions
#   source  = "lablabs/eks-alb-ingress/aws"
#   version = "0.5.0"
#   cluster_identity_oidc_issuer = ""
#   cluster_identity_oidc_issuer_arn = ""
#   cluster_name = local.cluster_name
# }

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
          name = "ghcr"
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
    labels = {
      app = "signalserver"
    }
  }
  spec {
    type = "ClusterIP"
    selector = {
      app = "signalserver"
    }
    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress" "signalserver" {
  metadata {
    name = "signalserver-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "alb"
      #"alb.ingress.kubernetes.io/group.name" = "my-group" # to share an alb with multiple ingressess
    }
  }
  spec {
    backend {
      service_name = kubernetes_service.signalserver.metadata.0.name
      service_port = kubernetes_service.signalserver.spec.0.port.0.port
    }
    rule {
      host = "tradesignalserver.com"
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

# # Create a local variable for the load balancer name.
# locals {
#   lb_name = split("-", split(".", kubernetes_service.signalserver.status.0.load_balancer.0.ingress.0.hostname).0).0
# }

# # Read information about the load balancer using the AWS provider.
# data "aws_elb" "signals" {
#   name = local.lb_name
# }

# output "load_balancer_name" {
#   value = local.lb_name
# }

# output "load_balancer_hostname" {
#   value = kubernetes_service.signalserver.status.0.load_balancer.0.ingress.0.hostname
# }

# output "load_balancer_info" {
#   value = data.aws_elb.signals
# }